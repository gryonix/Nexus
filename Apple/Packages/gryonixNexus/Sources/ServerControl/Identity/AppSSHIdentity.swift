import CryptoKit
import Foundation

public struct AppSSHIdentity: Sendable, Hashable {
    public let privateKeySeed: Data
    /// Full authorized_keys line: "ssh-ed25519 <base64> gryonixnexus-app"
    public let publicKeyOpenSSH: String

    public init(privateKeySeed: Data) throws {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeySeed)
        self.privateKeySeed = privateKeySeed
        self.publicKeyOpenSSH = OpenSSHPublicKey.encode(
            ed25519PublicKey: key.publicKey.rawRepresentation,
            comment: OpenSSHPublicKey.defaultComment
        )
    }

    public static func generate() -> AppSSHIdentity {
        // Force-try is safe: a freshly generated key always round-trips.
        try! AppSSHIdentity(privateKeySeed: Curve25519.Signing.PrivateKey().rawRepresentation)
    }
}

public enum OpenSSHPublicKey {
    public static let defaultComment = "gryonixnexus-app"

    public static func encode(ed25519PublicKey: Data, comment: String) -> String {
        var blob = Data()
        appendString("ssh-ed25519", to: &blob)
        appendString(ed25519PublicKey, to: &blob)
        return "ssh-ed25519 \(blob.base64EncodedString()) \(comment)"
    }

    private static func appendString(_ string: String, to blob: inout Data) {
        appendString(Data(string.utf8), to: &blob)
    }

    private static func appendString(_ data: Data, to blob: inout Data) {
        var length = UInt32(data.count).bigEndian
        withUnsafeBytes(of: &length) { blob.append(contentsOf: $0) }
        blob.append(data)
    }
}

public protocol SSHIdentityStore: Sendable {
    func load() throws -> AppSSHIdentity?
    func save(_ identity: AppSSHIdentity) throws
    func delete() throws
}

extension SSHIdentityStore {
    public func loadOrGenerate() throws -> AppSSHIdentity {
        if let existing = try load() { return existing }
        let fresh = AppSSHIdentity.generate()
        try save(fresh)
        return fresh
    }
}
