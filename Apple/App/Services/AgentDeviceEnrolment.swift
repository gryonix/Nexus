import AgentClient
import Foundation
import ServerControl
import ServerControlSSH
#if canImport(UIKit)
import UIKit
#endif

/// Putting THIS device into a server's paired-device registry
@available(macOS 15.0, *)
enum AgentDeviceEnrolment {
    /// The label the agent records for this device
    static var deviceLabel: String { ThisDeviceName.current }

    static func pairingCode(session: AgentConnection.Session, deployment: Deployment) async throws -> String {
        let exec = try await session.runner.run(
            AgentAdoption.pairCodeCommand, on: deployment.servicesHost,
            timeout: .seconds(deployment.timeouts.quickSeconds))
        guard exec.succeeded, let code = PairingCode.parse(exec.stdout) else {
            let detail = exec.stderr.isEmpty ? exec.stdout : exec.stderr
            throw AgentAdoptionError.pairCodeUnavailable(
                detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return code
    }

    static func enrol(session: AgentConnection.Session,
                      deployment: Deployment,
                      label: String = deviceLabel) async throws -> Gryonixnexusd_V1_Device {
        let code = try await pairingCode(session: session, deployment: deployment)
        let identity = try await Task.detached(priority: .userInitiated) {
            try KeychainSSHIdentityStore(deploymentID: deployment.id).loadOrGenerate()
        }.value
        let uid = await Task.detached(priority: .userInitiated) { DeviceIdentity.uid }.value
        return try await session.client.pair(code: code,
                                             devicePublicKey: identity.publicKeyOpenSSH,
                                             label: label,
                                             deviceUID: uid)
    }

    static func needsEnrolment(devices: [Gryonixnexusd_V1_Device],
                               thisDevicePublicKey: String?) -> Bool {
        guard let key = thisDevicePublicKey, !key.isEmpty else { return false }
        return !devices.contains { $0.publicKey == key }
    }

    static func publicKey(for deployment: Deployment) async -> String? {
        try? await Task.detached(priority: .userInitiated) {
            try KeychainSSHIdentityStore(deploymentID: deployment.id).loadOrGenerate().publicKeyOpenSSH
        }.value
    }

    static func ensureRegistered(session: AgentConnection.Session,
                                 deployment: Deployment,
                                 devices: [Gryonixnexusd_V1_Device],
                                 thisDevicePublicKey: String?,
                                 onFailure: (String) -> Void) async -> [Gryonixnexusd_V1_Device] {
        guard needsEnrolment(devices: devices, thisDevicePublicKey: thisDevicePublicKey) else {
            return devices
        }
        do {
            let device = try await enrol(session: session, deployment: deployment)
            return devices + [device]
        } catch {
            onFailure((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return devices
        }
    }
}
