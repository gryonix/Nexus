import Foundation
import VPNTunnel
#if os(macOS)
import os
@preconcurrency import SystemExtensions
#endif

/// Which tunnel bundle this build carries
enum MacTunnelPackaging {
    static let appExtensionID = "com.skaymer.gryonixnexus.tunnel"
    static let systemExtensionID = "com.skaymer.gryonixnexus.tunnel.system"

    /// Release Mac builds start the system extension
    static var usesSystemExtension: Bool {
        #if os(macOS)
        let wanted = Bundle.main.object(forInfoDictionaryKey: "GXMacTunnel") as? String
        let sysex = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Library/SystemExtensions/\(systemExtensionID).systemextension")
        return wanted == "system-extension" && FileManager.default.fileExists(atPath: sysex.path)
        #else
        return false
        #endif
    }

    static let proxyAppExtensionID = "com.skaymer.gryonixnexus.proxytunnel"
    static let proxySystemExtensionID = "com.skaymer.gryonixnexus.proxytunnel.system"

    /// The tunnel bundles this build starts, one per engine
    static var providers: TunnelProviders {
        usesSystemExtension
            ? TunnelProviders(wireGuard: systemExtensionID, proxy: proxySystemExtensionID)
            : .appExtensions
    }
}

/// WireGuard and the proxies run in separate tunnel processes
struct TunnelProviders: Sendable, Equatable {
    let wireGuard: String
    let proxy: String

    static let appExtensions = TunnelProviders(wireGuard: MacTunnelPackaging.appExtensionID,
                                               proxy: MacTunnelPackaging.proxyAppExtensionID)

    var all: [String] { [wireGuard, proxy] }

    func bundleID(for datapath: TunnelDatapath) -> String {
        datapath == .xray ? proxy : wireGuard
    }
}

#if os(macOS)
/// Asks macOS to turn the tunnel's system extension on
@MainActor
final class SystemExtensionActivator: NSObject {
    static let shared = SystemExtensionActivator()

    /// Shown while macOS waits for the user's approval
    var onNeedsApproval: (() -> Void)?

    private var waiting: [String: [CheckedContinuation<Void, Error>]] = [:]
    private var active: Set<String> = []
    private static let log = Logger(subsystem: "com.skaymer.gryonixnexus", category: "tunnel")

    /// Returns once both tunnels run, throwing when macOS refuses
    func activate() async throws {
        for identifier in [MacTunnelPackaging.systemExtensionID, MacTunnelPackaging.proxySystemExtensionID] {
            try await activate(identifier)
        }
    }

    private func activate(_ identifier: String) async throws {
        if active.contains(identifier) { return }
        try await withCheckedThrowingContinuation { continuation in
            waiting[identifier, default: []].append(continuation)
            guard waiting[identifier]?.count == 1 else { return }
            Self.log.notice("sysex: asking macOS to activate \(identifier, privacy: .public)")
            let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: identifier, queue: .main)
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    fileprivate func finish(_ identifier: String, _ error: Error?) {
        if error == nil { active.insert(identifier) }
        let pending = waiting.removeValue(forKey: identifier) ?? []
        for continuation in pending {
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        }
    }
}

extension SystemExtensionActivator: @preconcurrency OSSystemExtensionRequestDelegate {
    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        Self.log.notice("sysex: replacing \(existing.bundleShortVersion, privacy: .public) with \(ext.bundleShortVersion, privacy: .public)")
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Self.log.notice("sysex: waiting for the user's approval")
        onNeedsApproval?()
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Self.log.notice("sysex: active, result \(result.rawValue, privacy: .public)")
        finish(request.identifier, nil)
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Self.log.error("sysex: refused: \(String(describing: error), privacy: .public)")
        finish(request.identifier, error)
    }
}
#endif
