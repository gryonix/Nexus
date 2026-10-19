import Combine
import Foundation
import gryonixNexusCore

/// What this copy may do: demo, active or expired.
@MainActor
final class LicenseStore: ObservableObject {
    static let shared = LicenseStore()

    enum Status: Equatable {
        case demo
        case active(plan: LicenseToken.Plan, expires: Date?, viaAppStore: Bool)
        case expired
    }

    @Published private(set) var status: Status = .demo {
        didSet { Self.setUnlocked(status.isActive) }
    }
    @Published private(set) var code: String?

    private let keychain = KeychainStore()
    private static let tokenAccount = "license-token"
    private static let codeAccount = "license-code"
    nonisolated private static let everActiveKey = "licenseWasActive"
    private static let usedPendingKey = "licenseUsedPending"
    private static let usedSentKey = "licenseUsedSent"
    private static let renewWindow: TimeInterval = 7 * 24 * 3600
    private var appStorePlan: (plan: LicenseToken.Plan, expires: Date?)?

    private init() {
        reload()
    }

    func reload(now: Date = Date()) {
        code = try? keychain.string(for: Self.codeAccount)
        status = Self.testOverride ?? Self.derive(
            token: storedToken(now: now), appStore: appStorePlan,
            everActive: UserDefaults.standard.bool(forKey: Self.everActiveKey))
        if status.isActive, Self.testOverride == nil {
            UserDefaults.standard.set(true, forKey: Self.everActiveKey)
        }
    }

    static func derive(token: LicenseToken?, appStore: (plan: LicenseToken.Plan, expires: Date?)?,
                       everActive: Bool) -> Status {
        if let appStore, appStore.plan == .lifetime || token == nil {
            return .active(plan: appStore.plan, expires: appStore.expires, viaAppStore: true)
        }
        if let token { return .active(plan: token.plan, expires: token.expires, viaAppStore: false) }
        return everActive ? .expired : .demo
    }

    nonisolated static var wasEverActive: Bool {
        if let override = testOverride { return override == .expired }
        return UserDefaults.standard.bool(forKey: everActiveKey)
    }

    nonisolated private static var testOverride: Status? { nil }

    func setAppStoreEntitlement(_ plan: LicenseToken.Plan?, expires: Date?) {
        appStorePlan = plan.map { ($0, expires) }
        reload()
    }

    func activate(code input: String) async throws {
        guard let normalized = ActivationCode.normalize(input) else { throw LicenseAPI.Failure.unknownCode }
        try apply(try await LicenseAPI.activate(code: normalized), code: normalized)
    }

    /// Verifies and stores a grant from the server.
    func apply(_ grant: LicenseAPI.Grant, code fallback: String? = nil) throws {
        guard let token = grant.token else { throw LicenseAPI.Failure.rejected }
        do {
            _ = try LicenseToken.verify(token, device: DeviceIdentity.uid)
        } catch LicenseToken.VerificationError.otherProduct {
            throw LicenseAPI.Failure.wrongProduct
        }
        try keychain.set(token, for: Self.tokenAccount)
        if let code = grant.code ?? fallback { try keychain.set(code, for: Self.codeAccount) }
        reload()
    }

    /// Remembers a code without activating this device.
    func remember(code: String) {
        try? keychain.set(code, for: Self.codeAccount)
        self.code = code
    }

    /// Sends the used mark, retrying until it arrives.
    func noteFirstGeneration() async {
        guard !UserDefaults.standard.bool(forKey: Self.usedSentKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.usedPendingKey)
        await sendUsedMark()
    }

    private func sendUsedMark() async {
        guard UserDefaults.standard.bool(forKey: Self.usedPendingKey), let code else { return }
        if (try? await LicenseAPI.markUsed(code: code, device: DeviceIdentity.uid)) != nil {
            UserDefaults.standard.set(false, forKey: Self.usedPendingKey)
            UserDefaults.standard.set(true, forKey: Self.usedSentKey)
        }
    }

    func removeFromThisDevice() async {
        if let code { try? await LicenseAPI.deactivate(code: code, device: DeviceIdentity.uid) }
        try? keychain.delete(Self.tokenAccount)
        try? keychain.delete(Self.codeAccount)
        reload()
    }

    /// Renews a subscription token near its end.
    func refreshIfDue(now: Date = Date()) async {
        await sendUsedMark()
        guard let code, appStorePlan == nil else { return }
        let token = storedToken(now: now)
        if let token, token.expires == nil { return }
        if let end = token?.expires, end.timeIntervalSince(now) > Self.renewWindow { return }
        if let grant = try? await LicenseAPI.activate(code: code) { try? apply(grant, code: code) }
        reload(now: now)
    }

    private func storedToken(now: Date) -> LicenseToken? {
        guard let text = try? keychain.string(for: Self.tokenAccount) else { return nil }
        return try? LicenseToken.verify(text, device: DeviceIdentity.uid, now: now)
    }

    nonisolated private static let unlockedLock = NSLock()
    nonisolated(unsafe) private static var unlockedStorage = false

    /// Readable from any thread, for the session gate.
    nonisolated static var isUnlocked: Bool {
        unlockedLock.lock()
        defer { unlockedLock.unlock() }
        return unlockedStorage
    }

    private static func setUnlocked(_ value: Bool) {
        unlockedLock.lock()
        unlockedStorage = value
        unlockedLock.unlock()
    }
}

extension LicenseStore.Status {
    var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}
