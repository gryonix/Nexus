import AgentClient
import AgentControl
import Foundation
import ServerControl
import ServiceCatalog

/// Moving the VPN between home and the relay
extension DashboardViewModel {
    /// Whether the VPN section offers the move at all
    var offersVPNMove: Bool {
        deployment.canRunVPNOnRelay && !deployment.installedVPNServices.isEmpty
            && Self.agentTransportAvailable
    }

    /// Moves the VPN, keys and devices, to the other machine
    @discardableResult
    func moveVPN(toRelay: Bool) async -> Deployment? {
        guard offersVPNMove, deployment.vpnRunsOnRelay != toRelay, #available(macOS 15.0, *) else { return nil }
        let operation = LongOperationState(
            title: UIL10n.string(toRelay ? "Moving the VPN to the VPS" : "Moving the VPN home"),
            progressText: UIL10n.string("Packing the VPN's keys and devices…"))
        present(operation)
        defer { operation.isFinished = true }
        do {
            let moved = try await carryVPN(toRelay: toRelay, operation: operation)
            operation.progressText = UIL10n.string(toRelay
                ? "The VPN runs on the VPS now. Devices keep their configurations."
                : "The VPN runs at home now. Devices keep their configurations.")
            return moved
        } catch {
            operation.errorMessage = Self.message(for: error)
            return nil
        }
    }

    @available(macOS 15.0, *)
    private func carryVPN(toRelay: Bool, operation: LongOperationState) async throws -> Deployment {
        let before = deployment
        guard let target = before.otherVPNHost else { throw VPNMoveError.noSecondMachine }
        let state = try await agent(on: before.vpnHost).exportVPNState(directories: before.vpnStateDirectories)
        note(UIL10n.string("Packed the VPN's folders: %@", state.directories.joined(separator: ", ")), operation)
        try await agent(on: target).importVPNState(state, replace: true)
        operation.progressText = UIL10n.string("Starting the VPN on the other machine…")
        operation.log += "\n"
        replaceDeployment(before.movingVPN(toRelay: toRelay))
        do {
            try await installVPNHere(operation: operation)
        } catch {
            await undoMove(back: before, clearing: target, operation: operation)
            throw error
        }
        keep(deployment)
        await finishMove(retiring: before.vpnHost, operation: operation)
        return deployment
    }

    @available(macOS 15.0, *)
    private func agent(on host: SSHHostID) async throws -> AgentClient {
        try await AgentConnection.client(deployment: deployment, runner: try await session(), host: host)
    }

    /// Installs every VPN protocol of the deployment on its machine
    @available(macOS 15.0, *)
    private func installVPNHere(operation: LongOperationState) async throws {
        let protocols = deployment.installedVPNServices.intersection(ServiceID.vpnProtocols)
        guard let anchorID = ServiceRegistry.all.map(\.id).first(where: protocols.contains),
              let anchor = ServiceRegistry.service(anchorID) else { throw VPNMoveError.nothingToMove }
        try await installForMove(anchor, alsoProtocols: protocols, operation: operation)
    }

    /// Removes the old copy, data kept
    @available(macOS 15.0, *)
    private func finishMove(retiring oldHost: SSHHostID, operation: LongOperationState) async {
        do {
            try await removeVPN(on: oldHost)
        } catch {
            note(UIL10n.string("The old copy of the VPN is still running: %@", Self.message(for: error)), operation)
        }
        if !deployment.vpnRunsOnRelay { await updateRelay(operation: operation) }
    }

    /// Puts the VPN back and clears the other machine
    @available(macOS 15.0, *)
    private func undoMove(back before: Deployment, clearing target: SSHHostID,
                          operation: LongOperationState) async {
        replaceDeployment(before)
        try? await removeVPN(on: target)
        if !before.vpnRunsOnRelay { await updateRelay(operation: operation) }
    }

    @available(macOS 15.0, *)
    private func updateRelay(operation: LongOperationState) async {
        do {
            for line in try await reprovisionRelay() { note(line, operation) }
        } catch {
            note(UIL10n.string("Could not update the relay: %@", Self.message(for: error)), operation)
        }
    }

    /// Stops the VPN there, keeping its data and panel guard
    @available(macOS 15.0, *)
    private func removeVPN(on host: SSHHostID) async throws {
        guard let panel = ServiceRegistry.service(.vpnPanel) else { return }
        let client = try await agent(on: host)
        let lockdown = AgentAdminLockdown(client: client, gate: agentGate)
        let kept = try? await lockdown.status()
        try await AgentServiceRemoval(client: client, gate: agentGate).remove(panel, purge: .none) { _ in }
        if let kept, kept.isActive { _ = try? await lockdown.restore(kept) }
    }

    /// Saves where the VPN runs, whoever opened this screen
    private func keep(_ moved: Deployment) {
        try? FileDeploymentStore().upsert(moved)
        onDeploymentCorrected?(moved)
    }

    private func note(_ line: String, _ operation: LongOperationState) {
        operation.log += operation.log.isEmpty ? line : "\n" + line
    }
}

enum VPNMoveError: LocalizedError {
    case noSecondMachine
    case nothingToMove

    var errorDescription: String? {
        switch self {
        case .noSecondMachine: UIL10n.string("This server has no VPS in front of it.")
        case .nothingToMove: UIL10n.string("This server has no VPN to move.")
        }
    }
}
