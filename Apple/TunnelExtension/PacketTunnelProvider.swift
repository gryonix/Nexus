import NetworkExtension
import VPNProfile

#if canImport(WireGuardKit) && !GRYONIX_PROXY_TUNNEL
import WireGuardKit
#endif

#if canImport(OpenVPNAdapter)
import OpenVPNAdapter
#endif

/// The on-device datapath — all of them
class PacketTunnelProvider: NEPacketTunnelProvider {
    private var openVPNStarted: ((Error?) -> Void)?
    private let pulse = TunnelPulse()

    enum TunnelError: LocalizedError {
        case missingConfig
        case unknownDatapath(String)
        case datapathNotIntegrated(String)
        case badConfig(String)

        var errorDescription: String? {
            switch self {
            case .missingConfig:
                return "The tunnel has no configuration."
            case .unknownDatapath(let name):
                return "The tunnel names a datapath this build has no branch for: \(name)."
            case .datapathNotIntegrated(let name):
                return "The \(name) datapath is not integrated in this build."
            case .badConfig(let reason):
                return "The configuration could not be used: \(reason)"
            }
        }
    }

    private func storedConfig() -> String? {
        let proto = protocolConfiguration as? NETunnelProviderProtocol
        let configuration = proto?.providerConfiguration
        let kept = (configuration?[VPNTunnelKeys.configAccount] as? String)
            .flatMap { SharedTunnelSecret.secret(account: $0) }
        let text = kept ?? configuration?[VPNTunnelKeys.config] as? String
        return text?.isEmpty == false ? text : nil
    }

    /// The address the app pinned for this server, if any
    private func storedPin() -> EndpointPin? {
        EndpointPin(providerConfiguration: (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration)
    }

    private func storedDatapath() -> String {
        let proto = protocolConfiguration as? NETunnelProviderProtocol
        let name = proto?.providerConfiguration?[VPNTunnelKeys.datapath] as? String
        return name?.isEmpty == false ? name! : VPNTunnelKeys.wireGuardKit
    }

    /// A Go panic lands in the app group, not nowhere
    private static func keepGoCrashes() {
        guard let path = TunnelStopRecord().crashURL?.path else { return }
        if let answer = GryonixCrashOutput(path) { free(answer) }
    }

    static func carried(_ error: Error) -> NSError {
        NSError(domain: "com.skaymer.gryonixnexus.tunnel", code: (error as NSError).code,
                userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
    }

    override func cancelTunnelWithError(_ error: Error?) {
        TunnelStopRecord().note(error.map { "Tunnel: \($0.localizedDescription)" } ?? "Tunnel: cancelled with no error")
        super.cancelTunnelWithError(error.map(Self.carried))
    }

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler systemHandler: @escaping (Error?) -> Void) {
        let completionHandler: (Error?) -> Void = { error in
            if let error { TunnelStopRecord().note("Start: \(error.localizedDescription)") }
            systemHandler(error.map(Self.carried))
        }
        TunnelStopRecord().clear()
        pulse.start()
        Self.keepGoCrashes()
        guard let text = storedConfig() else {
            completionHandler(TunnelError.missingConfig)
            return
        }
        switch storedDatapath() {
        case VPNTunnelKeys.wireGuardKit:
            startWireGuard(text, completionHandler)
        case VPNTunnelKeys.xray:
            startXray(text, completionHandler)
        case VPNTunnelKeys.openVPN:
            startOpenVPN(text, completionHandler)
        case let other:
            completionHandler(TunnelError.unknownDatapath(other))
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        TunnelStopRecord().write(reason: reason.rawValue)
        switch storedDatapath() {
        case VPNTunnelKeys.xray: stopXray(completionHandler)
        case VPNTunnelKeys.openVPN: stopOpenVPN(completionHandler)
        default: stopWireGuard(completionHandler)
        }
    }

    /// The app asking how much has gone through
    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)?) {
        guard messageData == TunnelProviderMessage.statisticsRequest else {
            completionHandler?(nil)
            return
        }
        statistics { completionHandler?($0.encoded()) }
    }

    /// Whatever the datapath in force is counting
    private func statistics(_ answer: @escaping (TunnelProviderMessage.Statistics) -> Void) {
        switch storedDatapath() {
        case VPNTunnelKeys.xray:
            answer(proxyStatistics())
        case VPNTunnelKeys.openVPN:
            answer(openVPNStatistics())
        default:
            wireGuardStatistics(answer)
        }
    }

    // MARK: - WireGuard and AmneziaWG

    #if canImport(WireGuardKit) && !GRYONIX_PROXY_TUNNEL

    private lazy var adapter: WireGuardAdapter = {
        WireGuardAdapter(with: self) { level, message in
            NSLog("[gryonixVPN.tunnel] \(level): \(message)")
        }
    }()

    private func startWireGuard(_ text: String,
                                _ completionHandler: @escaping (Error?) -> Void) {
        let configuration: TunnelConfiguration
        do {
            configuration = try TunnelConfigurationBuilder.make(
                from: WireGuardQuickConfig(parsing: text), name: "gryonixVPN", pin: storedPin())
        } catch {
            completionHandler(TunnelError.badConfig(error.localizedDescription))
            return
        }
        adapter.start(tunnelConfiguration: configuration) { adapterError in
            completionHandler(adapterError.map { TunnelError.badConfig($0.localizedDescription) })
        }
    }

    private func stopWireGuard(_ completionHandler: @escaping () -> Void) {
        adapter.stop { _ in completionHandler() }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func wake() {
        guard storedDatapath() == VPNTunnelKeys.wireGuardKit,
              let text = storedConfig(),
              let parsed = try? WireGuardQuickConfig(parsing: text),
              let configuration = try? TunnelConfigurationBuilder.make(from: parsed,
                                                                      name: "gryonixVPN",
                                                                      pin: storedPin())
        else { return }
        adapter.update(tunnelConfiguration: configuration) { _ in }
    }

    private func wireGuardStatistics(
        _ answer: @escaping (TunnelProviderMessage.Statistics) -> Void) {
        adapter.getRuntimeConfiguration { text in
            guard let text else { return answer(.init(received: 0, sent: 0)) }
            var received: Int64 = 0, sent: Int64 = 0, handshake: TimeInterval = 0
            for line in text.split(separator: "\n") {
                let pair = line.split(separator: "=", maxSplits: 1)
                guard pair.count == 2, let value = Int64(pair[1]) else { continue }
                switch pair[0] {
                case "rx_bytes": received += value
                case "tx_bytes": sent += value
                case "last_handshake_time_sec": handshake = max(handshake, TimeInterval(value))
                default: break
                }
            }
            answer(.init(received: received, sent: sent,
                         lastHandshake: handshake > 0
                             ? Date(timeIntervalSince1970: handshake) : nil))
        }
    }

    #else

    private func startWireGuard(_ text: String,
                                _ completionHandler: @escaping (Error?) -> Void) {
        completionHandler(TunnelError.datapathNotIntegrated("WireGuard (WireGuardKit)"))
    }

    private func stopWireGuard(_ completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    private func wireGuardStatistics(
        _ answer: @escaping (TunnelProviderMessage.Statistics) -> Void) {
        answer(.init(received: 0, sent: 0))
    }

    #endif

    // MARK: - Shadowsocks and Xray Reality

    #if GRYONIX_PROXY_TUNNEL

    /// Both halves of that datapath, held together — see `XrayDatapath`
    private let xray = XrayDatapath()

    private func startXray(_ text: String,
                           _ completionHandler: @escaping (Error?) -> Void) {
        Task {
            do {
                try await xray.start(link: text, on: self, pin: storedPin())
                completionHandler(nil)
            } catch {
                xray.stop()
                completionHandler(TunnelError.badConfig(error.localizedDescription))
            }
        }
    }

    private func stopXray(_ completionHandler: @escaping () -> Void) {
        xray.stop()
        completionHandler()
    }

    private func proxyStatistics() -> TunnelProviderMessage.Statistics {
        let counters = xray.counters
        return .init(received: Int64(counters.received), sent: Int64(counters.sent))
    }

    #else

    /// The proxies run in the proxy tunnel, not here
    private func startXray(_ text: String,
                           _ completionHandler: @escaping (Error?) -> Void) {
        completionHandler(TunnelError.datapathNotIntegrated("Shadowsocks / Xray"))
    }

    private func stopXray(_ completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    private func proxyStatistics() -> TunnelProviderMessage.Statistics {
        .init(received: 0, sent: 0)
    }

    #endif

    // MARK: - OpenVPN

    #if canImport(OpenVPNAdapter)

    private lazy var openVPN: OpenVPNAdapter = {
        let adapter = OpenVPNAdapter()
        adapter.delegate = self
        return adapter
    }()

    private func startOpenVPN(_ text: String,
                              _ completionHandler: @escaping (Error?) -> Void) {
        let configuration = OpenVPNConfiguration()
        configuration.fileContent = Data(text.utf8)
        do {
            _ = try openVPN.apply(configuration: configuration)
        } catch {
            completionHandler(TunnelError.badConfig(error.localizedDescription))
            return
        }
        openVPNStarted = completionHandler
        openVPN.connect(using: packetFlow)
    }

    private func stopOpenVPN(_ completionHandler: @escaping () -> Void) {
        openVPN.disconnect()
        completionHandler()
    }

    private func openVPNStatistics() -> TunnelProviderMessage.Statistics {
        let transport = openVPN.transportStatistics
        return .init(received: Int64(transport.bytesIn), sent: Int64(transport.bytesOut))
    }

    #else

    private func startOpenVPN(_ text: String,
                              _ completionHandler: @escaping (Error?) -> Void) {
        completionHandler(TunnelError.datapathNotIntegrated("OpenVPN (OpenVPNAdapter)"))
    }

    private func stopOpenVPN(_ completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    private func openVPNStatistics() -> TunnelProviderMessage.Statistics {
        .init(received: 0, sent: 0)
    }

    #endif
}

#if canImport(OpenVPNAdapter)
extension PacketTunnelProvider: OpenVPNAdapterDelegate {
    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter,
                        configureTunnelWithNetworkSettings networkSettings: NEPacketTunnelNetworkSettings?,
                        completionHandler: @escaping @Sendable (Error?) -> Void) {
        setTunnelNetworkSettings(networkSettings) { error in
            completionHandler(error)
        }
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter,
                        handleEvent event: OpenVPNAdapterEvent,
                        message: String?) {
        guard event == .connected else { return }
        openVPNStarted?(nil)
        openVPNStarted = nil
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleError error: Error) {
        let fatal = (error as NSError).userInfo[OpenVPNAdapterErrorFatalKey] as? Bool ?? false
        if let started = openVPNStarted {
            guard fatal else { return }
            openVPNStarted = nil
            started(TunnelError.badConfig(error.localizedDescription))
            return
        }
        guard fatal else { return }
        cancelTunnelWithError(TunnelError.badConfig(error.localizedDescription))
    }

    func openVPNAdapter(_ openVPNAdapter: OpenVPNAdapter, handleLogMessage logMessage: String) {
        NSLog("[gryonixVPN.tunnel] openvpn: \(logMessage)")
    }
}

extension NEPacketTunnelFlow: @retroactive OpenVPNAdapterPacketFlow {}
#endif
