import CryptoKit
import Foundation

public struct WireGuardKeyPair: Sendable, Hashable {
    public let privateKey: String
    public let publicKey: String

    public init(privateKey: String, publicKey: String) {
        self.privateKey = privateKey
        self.publicKey = publicKey
    }
}

public enum WireGuardKeySlot: String, Sendable, CaseIterable {
    case vps
    case home
}

public protocol WireGuardKeyProvider: Sendable {
    func makeKeyPair(for slot: WireGuardKeySlot) throws -> WireGuardKeyPair
}

public struct CryptoKitWireGuardKeyProvider: WireGuardKeyProvider {
    public init() {}

    public func makeKeyPair(for slot: WireGuardKeySlot) -> WireGuardKeyPair {
        let key = Curve25519.KeyAgreement.PrivateKey()
        return WireGuardKeyPair(
            privateKey: key.rawRepresentation.base64EncodedString(),
            publicKey: key.publicKey.rawRepresentation.base64EncodedString()
        )
    }
}
