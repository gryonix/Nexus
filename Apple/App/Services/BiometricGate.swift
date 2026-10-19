import Foundation
import LocalAuthentication

enum BiometricGate {
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return true
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

/// UserDefaults keys for the three independent gates
enum SecuritySettings {
    /// Require authentication to open the "Access & passwords" screen
    static let gateAccessScreenKey = "security.gateAccessScreen"
    /// Require authentication to reveal/copy an individual saved password
    static let gateRevealKey = "security.gateReveal"
    static let gateExportKey = "security.gateExport"
}
