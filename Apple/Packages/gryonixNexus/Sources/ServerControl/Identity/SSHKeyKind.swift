import Foundation

/// The key types the app can generate
public enum SSHKeyKind: String, Codable, CaseIterable, Sendable, Hashable {
    case ed25519
    case ecdsaP256
    case rsa3072
    case rsa4096

    public var algorithm: String {
        switch self {
        case .ed25519: return "ssh-ed25519"
        case .ecdsaP256: return "ecdsa-sha2-nistp256"
        case .rsa3072, .rsa4096: return "ssh-rsa"
        }
    }

    public var bits: Int {
        switch self {
        case .ed25519, .ecdsaP256: return 256
        case .rsa3072: return 3072
        case .rsa4096: return 4096
        }
    }

    /// The name ssh-keygen prints in the randomart header
    public var artName: String {
        switch self {
        case .ed25519: return "ED25519"
        case .ecdsaP256: return "ECDSA"
        case .rsa3072, .rsa4096: return "RSA"
        }
    }

    public var displayName: String {
        switch self {
        case .ed25519: return "Ed25519"
        case .ecdsaP256: return "ECDSA P-256"
        case .rsa3072: return "RSA 3072"
        case .rsa4096: return "RSA 4096"
        }
    }
}

/// One key the user generated
public struct UserSSHKey: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public let kind: SSHKeyKind
    public let createdAt: Date
    /// One authorized_keys line
    public let publicKey: String
    /// Unencrypted openssh-key-v1 PEM
    public let privateKeyPEM: String

    public init(id: UUID = UUID(), name: String, kind: SSHKeyKind, createdAt: Date = Date(),
                publicKey: String, privateKeyPEM: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
        self.publicKey = publicKey
        self.privateKeyPEM = privateKeyPEM
    }

    public var fingerprint: String { SSHFingerprint.sha256(publicKeyLine: publicKey) ?? "" }

    public var randomArt: String {
        SSHFingerprint.randomArt(publicKeyLine: publicKey, kind: kind) ?? ""
    }
}
