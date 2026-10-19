import CryptoKit
import Foundation
import MailRecipe

struct KeychainWireGuardKeyProvider: WireGuardKeyProvider {
    private let deploymentID: UUID
    private let keychain: KeychainStore

    init(deploymentID: UUID, keychain: KeychainStore = KeychainStore()) {
        self.deploymentID = deploymentID
        self.keychain = keychain
    }

    private func account(_ slot: WireGuardKeySlot) -> String {
        "wg-tunnel-\(deploymentID.uuidString)-\(slot.rawValue)"
    }

    func makeKeyPair(for slot: WireGuardKeySlot) throws -> WireGuardKeyPair {
        if let seed = try keychain.data(for: account(slot)),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: seed) {
            return WireGuardKeyPair(
                privateKey: key.rawRepresentation.base64EncodedString(),
                publicKey: key.publicKey.rawRepresentation.base64EncodedString()
            )
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try keychain.set(key.rawRepresentation, for: account(slot))
        return WireGuardKeyPair(
            privateKey: key.rawRepresentation.base64EncodedString(),
            publicKey: key.publicKey.rawRepresentation.base64EncodedString()
        )
    }

    /// Removes both stored pairs — called when the deployment is erased
    func deleteAll() {
        for slot in WireGuardKeySlot.allCases {
            try? keychain.delete(account(slot))
        }
    }

    /// Reads the stored seeds WITHOUT minting any — for export
    func storedSeeds() -> [WireGuardKeySlot: Data] {
        var result: [WireGuardKeySlot: Data] = [:]
        for slot in WireGuardKeySlot.allCases {
            if let seed = try? keychain.data(for: account(slot)) {
                result[slot] = seed
            }
        }
        return result
    }

    func restore(seeds: [WireGuardKeySlot: Data]) {
        for (slot, seed) in seeds {
            try? keychain.set(seed, for: account(slot))
        }
    }
}
