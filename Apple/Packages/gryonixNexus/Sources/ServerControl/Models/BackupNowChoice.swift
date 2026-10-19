import Foundation

/// What "Back up now" runs: services, encryption and key
public struct BackupNowChoice: Sendable, Hashable {
    /// Which password encrypts the archives
    public enum Key: Sendable, Hashable {
        /// The key the server already holds for its backups
        case stored
        /// A password typed for this run only
        case typed
    }

    /// Chosen services, raw IDs, in the order they run
    public var services: [String] = []
    /// Nil until changed: then the services' own default
    public var encrypt: Bool?
    public var key: Key = .stored
    public var passphrase = ""
    public var confirmation = ""

    public init(services: [String] = [], encrypt: Bool? = nil, key: Key = .stored) {
        self.services = services
        self.encrypt = encrypt
        self.key = key
    }

    public mutating func toggle(_ service: String) {
        if let index = services.firstIndex(of: service) {
            services.remove(at: index)
        } else {
            services.append(service)
        }
    }

    /// The toggle: as set, or on if a service encrypts
    public func encrypting(defaultsOn: Set<String>) -> Bool {
        encrypt ?? services.contains(where: defaultsOn.contains)
    }

    /// Whether one service's archive is encrypted
    public func encrypts(_ service: String, defaultsOn: Set<String>, alwaysEncrypted: Set<String>) -> Bool {
        alwaysEncrypted.contains(service) || encrypting(defaultsOn: defaultsOn)
    }

    /// Whether any chosen archive needs a key
    public func needsKey(defaultsOn: Set<String>, alwaysEncrypted: Set<String>) -> Bool {
        services.contains { encrypts($0, defaultsOn: defaultsOn, alwaysEncrypted: alwaysEncrypted) }
    }

    /// The password to send; nil means the server's stored key
    public var passphraseToSend: String? {
        key == .typed && !passphrase.isEmpty ? passphrase : nil
    }

    /// Whether the run can start; an unknown key is tried
    public func isReady(defaultsOn: Set<String>, alwaysEncrypted: Set<String>, hasStoredKey: Bool?) -> Bool {
        guard !services.isEmpty else { return false }
        guard needsKey(defaultsOn: defaultsOn, alwaysEncrypted: alwaysEncrypted) else { return true }
        switch key {
        case .stored: return hasStoredKey != false
        case .typed: return passphrase.count >= 8 && passphrase == confirmation
        }
    }

    /// The chosen services' sizes added up, or nil
    public static func total(_ estimates: [BackupEstimate]) -> BackupEstimate? {
        guard !estimates.isEmpty else { return nil }
        let data = estimates.reduce(UInt64(0)) { $0 &+ $1.dataBytes }
        return BackupEstimate(dataBytes: data, freeBytes: estimates.map(\.freeBytes).min() ?? 0)
    }
}
