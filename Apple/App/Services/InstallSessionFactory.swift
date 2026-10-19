import Foundation
import ServerControl
import ServerControlSSH

/// Composition root for a remote-install session
enum InstallSessionFactory {
    static func makeRunnerDetached(deployment: Deployment, address: String, port: Int,
                                   username: String, pinSlot: SSHHostID,
                                   secret: SSHSecret = .appKey) async throws -> any SSHCommandRunner & RemoteFileBrowser {
        try await Task.detached(priority: .userInitiated) {
            try makeRunner(deployment: deployment, address: address, port: port,
                           username: username, pinSlot: pinSlot, secret: secret)
        }.value
    }

    static func makeRunner(deployment: Deployment, address: String, port: Int,
                           username: String, pinSlot: SSHHostID,
                           secret: SSHSecret = .appKey) throws -> any SSHCommandRunner & RemoteFileBrowser {
        if DemoServer.isDemo(deployment) || !LicenseStore.isUnlocked {
            return DemoInstallRunner(deployment: deployment)
        }
        let pins = HostKeyPinStore(deploymentID: deployment.id)
        let identity = try KeychainSSHIdentityStore(deploymentID: deployment.id).loadOrGenerate()
        var password: String?
        var seed = identity.privateKeySeed
        switch secret {
        case .appKey:
            break
        case .password(let value):
            password = value
        case .privateKeySeed(let pasted):
            seed = pasted
        }
        let settings = SSHConnectionSettings(
            vpsHost: address,
            vpsPort: port,
            username: username,
            homeHost: "", // direct connection only; every command runs on .vps
            privateKeySeed: seed,
            passwords: password.map { [.vps: $0] } ?? [:],
            pinnedVPSHostKey: pins.pin(for: pinSlot)
        )
        return CitadelCommandRunner(settings: settings, onPinHostKey: { _, presentedKey in
            pins.store(presentedKey, for: pinSlot)
        })
    }
}
