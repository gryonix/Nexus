import Foundation

enum DeviceIdentity {
    private static let account = "device-uid"

    /// Read once per process
    private static let cached = LockedBox()

    /// This installation's id, minting one on first use
    static var uid: String {
        cached.value {
            let keychain = KeychainStore()
            let stored: Data?
            do {
                stored = try keychain.data(for: account)
            } catch {
                return nil
            }
            if let stored, let existing = String(data: stored, encoding: .utf8), !existing.isEmpty {
                return existing
            }
            let minted = UUID().uuidString
            guard (try? keychain.set(Data(minted.utf8), for: account)) != nil else { return nil }
            return minted
        } ?? ""
    }

    /// Forgets this installation's id
    static func forget() {
        try? KeychainStore().delete(account)
        cached.reset()
    }

    /// A tiny memoiser
    private final class LockedBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: String?

        /// Keeps only a real value; nil is retried next time
        func value(_ make: () -> String?) -> String? {
            lock.lock()
            defer { lock.unlock() }
            if let stored { return stored }
            let made = make()
            stored = made
            return made
        }

        func reset() {
            lock.lock()
            stored = nil
            lock.unlock()
        }
    }
}
