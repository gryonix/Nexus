import Foundation
import ServerControl
import SwiftUI

/// Refuses real servers and own data without a license.
enum LicenseGate {
    enum Reason: String, Identifiable {
        case unlock, renew
        var id: String { rawValue }
    }

    struct Locked: LocalizedError {
        let reason: Reason
        var errorDescription: String? { LicenseGate.message(for: reason) }
    }

    nonisolated static var reason: Reason {
        LicenseStore.wasEverActive ? .renew : .unlock
    }

    static func message(for reason: Reason) -> String {
        switch reason {
        case .unlock: return UIL10n.string("Unlock in the full version")
        case .renew: return UIL10n.string("Activate your subscription")
        }
    }

    /// Throws for a real server while locked.
    nonisolated static func check(_ deployment: Deployment) throws {
        guard !LicenseStore.isUnlocked, !DemoFleet.covers(deployment) else { return }
        throw Locked(reason: reason)
    }
}

/// The lock sheet raised from anywhere in the app.
@MainActor
final class LicensePrompt: ObservableObject {
    static let shared = LicensePrompt()
    @Published var reason: LicenseGate.Reason?

    private init() {}

    /// True when unlocked; otherwise shows the lock sheet.
    @discardableResult
    func allow() -> Bool {
        if LicenseStore.shared.status.isActive { return true }
        reason = LicenseGate.reason
        return false
    }

    /// Like `allow`, but demo servers always pass.
    @discardableResult
    func allow(_ deployment: Deployment) -> Bool {
        DemoFleet.covers(deployment) || allow()
    }
}
