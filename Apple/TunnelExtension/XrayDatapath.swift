#if GRYONIX_PROXY_TUNNEL
import Foundation
@preconcurrency import NetworkExtension
import VPNProfile

/// Shadowsocks and Xray Reality, on the device
final class XrayDatapath: @unchecked Sendable {
    enum Failure: LocalizedError {
        /// The proxy core refused the configuration
        case coreRefused(String)
        case noTunnelInterface
        case packetStackStopped

        var errorDescription: String? {
            switch self {
            case .coreRefused(let reason): return "The proxy core refused the configuration: \(reason)"
            case .noTunnelInterface: return "The tunnel interface could not be found."
            case .packetStackStopped: return "The packet stack stopped."
            }
        }
    }

    private let lock = NSLock()
    private var packetStack: Thread?
    private var isRunning = false

    /// Clears the running flag, returning its old value
    private func claimStop() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let was = isRunning
        isRunning = false
        packetStack = nil
        return was
    }

    /// Brings both halves up
    func start(link stored: String, on provider: NEPacketTunnelProvider,
               pin: EndpointPin? = nil) async throws {
        let (text, dns) = ProxyTunnelText.split(stored)
        let link = try ProxyLinkConfig(parsing: text)

        let access = LocalProxyAccess.random()
        let pinned = pin?.replacingHost(of: link.endpoint)
        var server = pinned ?? ""
        if pinned == nil { server = await Self.addressBeforeTunnel(link) }
        let remote = pinned == nil ? link.host : pin?.address ?? link.host
        try await provider.setTunnelNetworkSettings(Self.networkSettings(remote: remote, dns: dns))
        try Self.startCore(link: link, text: text, dns: dns, server: server, access: access)

        guard let fd = Self.tunnelFileDescriptor else {
            Self.stopCores()
            throw Failure.noTunnelInterface
        }

        let yaml = Tun2SocksConfiguration.yaml(access: access)
        let thread = Thread { [weak self] in
            let bytes = Array(yaml.utf8)
            _ = bytes.withUnsafeBufferPointer { buffer in
                hev_socks5_tunnel_main_from_str(buffer.baseAddress, UInt32(buffer.count), fd)
            }
            guard let self, self.claimStop() else { return }
            provider.cancelTunnelWithError(Failure.packetStackStopped)
        }
        thread.name = "com.skaymer.gryonixvpn.tunnel.tun2socks"
        thread.stackSize = 4 << 20
        lock.withLock {
            isRunning = true
            packetStack = thread
        }
        thread.start()
    }

    func stop() {
        guard claimStop() else { return }
        hev_socks5_tunnel_quit()
        Self.stopCores()
    }

    /// Go's soft ceiling, well under the extension's own limit
    private static let xrayMemoryLimit: Int64 = 24 << 20

    /// Shadowsocks runs our own client; everything else runs Xray
    private static func startCore(link: ProxyLinkConfig, text: String, dns: [String], server: String,
                                  access: LocalProxyAccess) throws {
        if case .shadowsocks(let method, let password) = link.credential {
            let listen = "127.0.0.1:\(access.port)"
            try check(GryonixSSStart(listen, server, method, password,
                                     access.username, access.password))
            return
        }
        let json = try XrayConfiguration.json(forLink: text, access: access,
                                              dns: ProxyTunnelText.reachableDNS(dns),
                                              serverAddress: serverAddress(of: server, link: link))
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let configURL = directory.appendingPathComponent("xray-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: configURL, options: [.completeFileProtectionUntilFirstUserAuthentication])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: configURL.path)
        defer { try? FileManager.default.removeItem(at: configURL) }
        try check(LibXrayRunXray(directory.path, configURL.path, xrayMemoryLimit))
    }

    /// The host part of `address:port`, or the link's own host
    private static func serverAddress(of server: String, link: ProxyLinkConfig) -> String {
        guard let cut = server.lastIndex(of: ":") else { return link.host }
        return String(server[..<cut]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    private static func check(_ pointer: UnsafeMutablePointer<CChar>?) throws {
        if let failure = answer(pointer), !failure.isEmpty {
            throw Failure.coreRefused(failure)
        }
    }

    private static func stopCores() {
        _ = answer(GryonixSSStop())
        _ = answer(LibXrayStopXray())
    }

    /// Bytes in and out, as lwIP counted them
    var counters: (received: UInt64, sent: UInt64) {
        lock.lock()
        let running = isRunning
        lock.unlock()
        guard running else { return (0, 0) }
        var txPackets = 0, txBytes = 0, rxPackets = 0, rxBytes = 0
        hev_socks5_tunnel_stats(&txPackets, &txBytes, &rxPackets, &rxBytes)
        return (UInt64(rxBytes), UInt64(txBytes))
    }

    // MARK: - The system's side of the tunnel

    /// What the system is told about the interface
    static func networkSettings(remote: String,
                                dns servers: [String] = ProxyTunnelText.fallbackDNS) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remoteAddress(remote))
        let ipv4 = NEIPv4Settings(addresses: [Tun2SocksConfiguration.address],
                                  subnetMasks: [Tun2SocksConfiguration.netmask])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        let ipv6 = NEIPv6Settings(addresses: [Tun2SocksConfiguration.address6], networkPrefixLengths: [64])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6
        settings.mtu = NSNumber(value: Tun2SocksConfiguration.mtu)
        let dns = NEDNSSettings(servers: ProxyTunnelText.reachableDNS(servers))
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        return settings
    }

    static func addressBeforeTunnel(_ link: ProxyLinkConfig) async -> String {
        let host = link.host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let resolved = await Task.detached { numericAddress(of: host) }.value
        guard let resolved else { return link.endpoint }
        return resolved.contains(":") ? "[\(resolved)]:\(link.port)" : "\(resolved):\(link.port)"
    }

    static func numericAddress(of host: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var found: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &found) == 0, let first = found else { return nil }
        defer { freeaddrinfo(found) }
        var addresses: [(family: Int32, text: String)] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let info = cursor {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer,
                           socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.append((info.pointee.ai_family, String(cString: buffer)))
            }
            cursor = info.pointee.ai_next
        }
        return (addresses.first { $0.family == AF_INET } ?? addresses.first)?.text
    }

    /// An IP literal for the system, else loopback
    static func remoteAddress(_ host: String) -> String {
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        var v4 = in_addr(), v6 = in6_addr()
        if inet_pton(AF_INET, bare, &v4) == 1 || inet_pton(AF_INET6, bare, &v6) == 1 {
            return bare
        }
        return "127.0.0.1"
    }

    private static func answer(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    private static var tunnelFileDescriptor: Int32? {
        var info = ctl_info()
        withUnsafeMutablePointer(to: &info.ctl_name) {
            $0.withMemoryRebound(to: CChar.self,
                                 capacity: MemoryLayout.size(ofValue: $0.pointee)) {
                _ = strcpy($0, "com.apple.net.utun_control")
            }
        }
        for fd: Int32 in 0...1024 {
            var address = sockaddr_ctl()
            var result: Int32 = -1
            var length = socklen_t(MemoryLayout.size(ofValue: address))
            withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    result = getpeername(fd, $0, &length)
                }
            }
            if result != 0 || address.sc_family != AF_SYSTEM { continue }
            if info.ctl_id == 0 {
                result = ioctl(fd, GryonixControlGetInfo, &info)
                if result != 0 { continue }
            }
            if address.sc_id == info.ctl_id { return fd }
        }
        return nil
    }
}
#endif
