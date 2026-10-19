import Foundation
import NIOCore
import NIOSSH
import ServerControl

final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, Sendable {
    private let hostLabel: String
    private let pinnedKey: String?
    private let onPin: @Sendable (String) -> Void

    init(hostLabel: String, pinnedKey: String?, onPin: @escaping @Sendable (String) -> Void) {
        self.hostLabel = hostLabel
        self.pinnedKey = pinnedKey
        self.onPin = onPin
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let presented = String(openSSHPublicKey: hostKey)
        guard let pinnedKey else {
            validationCompletePromise.succeed(())
            let onPin = self.onPin
            DispatchQueue.global(qos: .userInitiated).async { onPin(presented) }
            return
        }
        if pinnedKey == HostKeyPinAccounts.unreadable {
            validationCompletePromise.fail(ServerControlError.connectionFailed(
                "the saved host key of \(hostLabel) could not be read — unlock the device and try again"))
        } else if presented == pinnedKey {
            validationCompletePromise.succeed(())
        } else {
            validationCompletePromise.fail(ServerControlError.hostKeyMismatch(host: hostLabel))
        }
    }
}
