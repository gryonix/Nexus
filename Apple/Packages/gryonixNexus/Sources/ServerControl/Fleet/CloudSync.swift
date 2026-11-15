import CryptoKit
import Foundation

/// What the app keeps in iCloud
public enum CloudSyncMode: String, CaseIterable, Codable, Sendable {
    case off
    case apple
    case applePassword
    case withoutKeys

    public var syncs: Bool { self != .off }
    public var includesKeys: Bool { self == .apple || self == .applePassword }
    public var usesPassword: Bool { self == .applePassword }
}

/// One synced item as iCloud stores it
public struct CloudSyncEnvelope: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var modifiedAt: Date
    public var deleted: Bool
    public var sealed: Bool
    public var payload: Data

    public init(modifiedAt: Date, deleted: Bool = false, sealed: Bool = false, payload: Data = Data()) {
        self.version = Self.currentVersion
        self.modifiedAt = modifiedAt
        self.deleted = deleted
        self.sealed = sealed
        self.payload = payload
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) -> CloudSyncEnvelope? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let envelope = try? decoder.decode(Self.self, from: data),
              envelope.version <= currentVersion else { return nil }
        return envelope
    }
}

/// The salt and check value behind a sync password
public struct CloudSyncPasswordLock: Codable, Sendable, Equatable {
    public var salt: Data
    public var verifier: Data
}

/// Seals synced items with a password-derived key
public enum CloudSyncSeal {
    static let check = Data("gryonixnexus-cloud-sync".utf8)

    /// A new lock and its key for a new password
    public static func lock(password: String) throws -> (CloudSyncPasswordLock, SymmetricKey) {
        let salt = TransferSeal.randomBytes(16)
        let key = try TransferSeal.deriveKey(password, salt: salt, iterations: TransferSeal.iterations)
        return (CloudSyncPasswordLock(salt: salt, verifier: try seal(check, key: key)), key)
    }

    /// The key for an existing lock, or a throw
    public static func unlock(_ lock: CloudSyncPasswordLock, password: String) throws -> SymmetricKey {
        let key = try TransferSeal.deriveKey(password, salt: lock.salt, iterations: TransferSeal.iterations)
        guard (try? open(lock.verifier, key: key)) == check else { throw TransferSeal.Failure.wrongPassphrase }
        return key
    }

    /// Whether a stored key still opens the lock
    public static func fits(_ key: SymmetricKey, _ lock: CloudSyncPasswordLock) -> Bool {
        (try? open(lock.verifier, key: key)) == check
    }

    public static func seal(_ plain: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key).combined else {
            throw TransferSeal.Failure.unreadable
        }
        return combined
    }

    public static func open(_ sealed: Data, key: SymmetricKey) throws -> Data {
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
        } catch {
            throw TransferSeal.Failure.wrongPassphrase
        }
    }
}

/// What this device last agreed with iCloud about one item
public struct CloudSyncMark: Codable, Sendable, Equatable {
    public var hash: String
    public var at: Date
    /// Removed on this device only; iCloud keeps it
    public var dismissed: Bool

    public init(hash: String, at: Date, dismissed: Bool = false) {
        self.hash = hash
        self.at = at
        self.dismissed = dismissed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hash = try container.decode(String.self, forKey: .hash)
        at = try container.decode(Date.self, forKey: .at)
        dismissed = try container.decodeIfPresent(Bool.self, forKey: .dismissed) ?? false
    }
}

/// What to do with one item
public enum CloudSyncDecision: Equatable, Sendable {
    case apply
    case delete
    case push
    case pushDeletion
    /// Forget it here and keep iCloud's copy
    case dismiss
    case nothing
}

/// Decides what to do with one synced item
public enum CloudSyncPlanner {
    public static func decide(remote: CloudSyncEnvelope?, localHash: String?, mark: CloudSyncMark?) -> CloudSyncDecision {
        guard let remote else { return localHash == nil ? .nothing : .push }
        let dismissed = mark?.dismissed == true
        if localHash == nil, dismissed { return .nothing }
        if isNewer(remote.modifiedAt, than: mark?.at) {
            if remote.deleted { return localHash == nil ? .nothing : .delete }
            return .apply
        }
        guard let localHash else {
            return remote.deleted || mark == nil ? .nothing : .dismiss
        }
        return localHash == mark?.hash && !remote.deleted && !dismissed ? .nothing : .push
    }

    /// Newer by more than the envelope's millisecond rounding
    static func isNewer(_ remote: Date, than mark: Date?) -> Bool {
        guard let mark else { return true }
        return remote.timeIntervalSince(mark) > 0.001
    }

    /// A stable name for a payload's content
    public static func hash(_ payload: Data) -> String {
        SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }
}
