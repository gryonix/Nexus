import Foundation

public enum WakeOnLAN {
    /// The port everything uses
    public static let port: UInt16 = 9

    public static func macBytes(_ text: String) -> [UInt8]? {
        let digits = text.filter { $0.isHexDigit }
        guard digits.count == 12,
              digits.count == text.filter({ !":-. ".contains($0) }).count else { return nil }
        var bytes: [UInt8] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    public static func normalised(_ text: String) -> String? {
        macBytes(text).map { $0.map { String(format: "%02x", $0) }.joined(separator: ":") }
    }

    public static func magicPacket(mac: String) -> Data? {
        guard let bytes = macBytes(mac) else { return nil }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: bytes) }
        return packet
    }

    /// Reaches every machine on the sender's own network
    public static let limitedBroadcast = "255.255.255.255"

    /// Prints the default interface's MAC, then its broadcast address
    public static let readCommand =
        "dev=$(ip route show default | awk '{print $5; exit}'); cat /sys/class/net/$dev/address; "
        + "ip -4 -o addr show dev \"$dev\" | awk '{for(i=1;i<=NF;i++) if($i==\"brd\"){print $(i+1); exit}}'"

    /// The MAC and broadcast address from `readCommand`
    public static func parseRead(_ output: String) -> (mac: String, broadcast: String?)? {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = lines.first, let mac = normalised(first) else { return nil }
        let broadcast = lines.dropFirst().first.flatMap { octets(of: $0) != nil ? $0 : nil }
        return (mac, broadcast)
    }

    /// Where to send: stored, from the address, or everywhere nearby
    public static func broadcast(stored: String?, host: String, resolved: String?) -> String {
        if let stored, octets(of: stored) != nil { return stored }
        return broadcastAddress(for: host) ?? resolved.flatMap(broadcastAddress(for:)) ?? limitedBroadcast
    }

    /// The first IPv4 address a name resolves to
    public static func resolveIPv4(_ host: String) async -> String? {
        await Task.detached {
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_DGRAM
            var list: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else { return nil }
            defer { freeaddrinfo(list) }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(first.pointee.ai_addr, first.pointee.ai_addrlen, &buffer,
                              socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
            return String(cString: buffer)
        }.value
    }

    public static func broadcastAddress(for host: String) -> String? {
        guard let octets = octets(of: host) else { return nil }
        return "\(octets[0]).\(octets[1]).\(octets[2]).255"
    }

    /// A private IPv4 address or an mDNS name
    public static func isLocalNetwork(_ host: String) -> Bool {
        if host.lowercased().hasSuffix(".local") { return true }
        guard let octets = octets(of: host) else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    /// Ports wake-up packets usually go to
    public static let ports: [UInt16] = [9, 7]

    /// Where this device sends: the network, everyone, the machine
    public static func deviceTargets(broadcast: String, host: String?) -> [String] {
        var targets = [broadcast, limitedBroadcast]
        if let host, octets(of: host) != nil { targets.append(host) }
        var seen = Set<String>()
        return targets.filter { seen.insert($0).inserted }
    }

    public static func command(mac: String, broadcast: String) -> String? {
        guard let bytes = macBytes(mac), octets(of: broadcast) != nil else { return nil }
        let packet = [UInt8](repeating: 0xFF, count: 6)
            + Array(repeating: bytes, count: 16).flatMap { $0 }
        let escaped = packet.map { String(format: "\\x%02x", $0) }.joined()
        let hex = packet.map { String(format: "%02x", $0) }.joined()
        let broadcastSend = "python3 -c 'import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); "
            + "s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1); "
            + "s.sendto(bytes.fromhex(\"\(hex)\"), (\"\(broadcast)\", \(port)))' 2>/dev/null"
        return "\(broadcastSend) || bash -c 'printf \"\(escaped)\" > /dev/udp/\(broadcast)/\(port)'"
    }

    /// One IPv4 address of this device with its netmask
    public struct DeviceAddress: Sendable, Hashable {
        public let address: String
        public let netmask: String

        public init(address: String, netmask: String) {
            self.address = address
            self.netmask = netmask
        }
    }

    /// Whether we share the machine's network, or nil if unknown
    public static func sharesNetwork(device: [DeviceAddress], machine: String?, broadcast: String?) -> Bool? {
        let subnets = device.compactMap { entry -> (UInt32, UInt32)? in
            guard let address = number(entry.address), let mask = number(entry.netmask) else { return nil }
            return (address, mask)
        }
        if let machine = machine.flatMap(number) {
            return subnets.contains { address, mask in address & mask == machine & mask }
        }
        if let broadcast = broadcast.flatMap(number), broadcast != 0xFFFF_FFFF {
            return subnets.contains { address, mask in address & mask == broadcast & mask && mask != 0xFFFF_FFFF }
        }
        return nil
    }

    private static func number(_ text: String) -> UInt32? {
        octets(of: text).map { $0.reduce(0) { $0 << 8 | UInt32($1) } }
    }

    private static func octets(of host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [UInt8] = []
        for part in parts {
            guard let value = UInt8(part), String(value) == String(part) else { return nil }
            octets.append(value)
        }
        return octets
    }
}
