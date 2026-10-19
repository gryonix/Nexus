import Foundation
import LocalAuthentication
import Network

/// Where a system permission stands.
enum PermissionState: Equatable {
    case notAsked
    case asking
    case granted
    case denied
    case unavailable
}

/// Triggers and reads the local network permission.
enum LocalNetworkPermission {
    static let serviceType = "_gryonixnexus._tcp"
    private static let timeout: Duration = .seconds(30)

    /// Advertises a service and browses until the system answers.
    @MainActor
    static func request() async -> PermissionState {
        let probe = LocalNetworkProbe(serviceType: serviceType)
        return await withTaskGroup(of: PermissionState.self) { group in
            group.addTask { await probe.run() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .notAsked
            }
            let first = await group.next() ?? .notAsked
            group.cancelAll()
            await probe.stop()
            return first
        }
    }
}

private actor LocalNetworkProbe {
    private let serviceType: String
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var continuation: CheckedContinuation<PermissionState, Never>?

    init(serviceType: String) {
        self.serviceType = serviceType
    }

    func run() async -> PermissionState {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            startListener()
            startBrowser()
        }
    }

    func stop() {
        listener?.cancel()
        browser?.cancel()
        finish(.notAsked)
    }

    private func finish(_ state: PermissionState) {
        continuation?.resume(returning: state)
        continuation = nil
    }

    private func startListener() {
        guard let listener = try? NWListener(using: .tcp) else { return }
        listener.service = NWListener.Service(name: UUID().uuidString, type: serviceType)
        listener.newConnectionHandler = { $0.cancel() }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func startBrowser() {
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            guard case .waiting(let error) = state, Self.isPolicyDenial(error) else { return }
            Task { await self?.finish(.denied) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard !results.isEmpty else { return }
            Task { await self?.finish(.granted) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private static func isPolicyDenial(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) }
        return false
    }
}

/// Face ID, Touch ID or Optic ID.
enum BiometricPermission {
    static let grantedKey = "onboarding.biometricsGranted"

    static var kind: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    static var currentState: PermissionState {
        guard kind != .none else { return .unavailable }
        return UserDefaults.standard.bool(forKey: grantedKey) ? .granted : .notAsked
    }

    /// Asks once so later prompts are never a surprise.
    static func request(reason: String) async -> PermissionState {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return kind == .none ? .unavailable : .denied
        }
        let granted = (try? await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)) ?? false
        UserDefaults.standard.set(granted, forKey: grantedKey)
        return granted ? .granted : .denied
    }
}
