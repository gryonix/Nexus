import Foundation
import ServerControl
import ServerControlSSH
import SwiftUI

@available(macOS 15.0, *)
@MainActor
final class TerminalSessions: ObservableObject {
    static let shared = TerminalSessions()

    private var storage: [UUID: TerminalController] = [:]

    @Published private(set) var live: [UUID: TerminalController] = [:]

    /// The profile whose screen opens once its list loads
    @Published var pendingOpen: UUID?

    private let savedStore = SavedTerminalSessionsStore()
    private var saved: SavedTerminalSessions
    private var restored = false

    private init() {
        saved = savedStore.load()
    }

    struct RestoreTarget {
        let deployment: Deployment
        let directHost: TerminalDirectHost?
        let profileID: UUID
    }

    func controller(for profile: TerminalProfile, on deployment: Deployment) -> TerminalController {
        if let existing = storage[profile.id] {
            remember(profile, on: deployment)
            return existing
        }
        let controller = TerminalController(deployment: deployment, profile: profile)
        storage[profile.id] = controller
        remember(profile, on: deployment)
        publishSoon()
        return controller
    }

    func existing(for profile: TerminalProfile) -> TerminalController? {
        storage[profile.id]
    }

    func end(_ profile: TerminalProfile) {
        storage[profile.id]?.disconnect()
        storage[profile.id] = nil
        saved.close(profileID: profile.id)
        savedStore.save(saved)
        publishSoon()
    }

    func endAll(for deploymentID: UUID) {
        for (id, controller) in storage where controller.deployment.id == deploymentID {
            controller.disconnect()
            storage[id] = nil
        }
        saved.closeAll(deploymentID: deploymentID)
        savedStore.save(saved)
        publishSoon()
    }

    private func remember(_ profile: TerminalProfile, on deployment: Deployment) {
        guard saved.selected != profile.id else { return }
        saved.open(SavedTerminalSession(profileID: profile.id, deploymentID: deployment.id,
                                        nodeID: profile.nodeID, username: profile.username))
        savedStore.save(saved)
    }

    /// Reconnects last run sessions; returns the one to show
    func restoreSaved() -> RestoreTarget? {
        guard !restored else { return nil }
        restored = true
        let servers = (try? FileDeploymentStore().load()) ?? []
        let hosts = (try? TerminalDirectHostStore().load()) ?? []
        let selected = saved.selected
        var shown: RestoreTarget?
        for record in saved.records {
            let host = hosts.first { $0.id == record.deploymentID }
            guard let deployment = servers.first(where: { $0.id == record.deploymentID }) ?? host?.deployment,
                  let profile = TerminalProfileStore(deploymentID: deployment.id).load()
                    .first(where: { $0.id == record.profileID })
            else {
                saved.close(profileID: record.profileID)
                continue
            }
            let controller = controller(for: profile, on: deployment)
            if record.profileID == selected {
                shown = RestoreTarget(deployment: deployment, directHost: host, profileID: profile.id)
            } else {
                Task { await controller.startResolved() }
            }
        }
        if let selected { saved.select(selected) }
        savedStore.save(saved)
        return shown
    }

    private var publishPending = false

    private func publishSoon() {
        guard !publishPending else { return }
        publishPending = true
        Task { @MainActor in
            self.publishPending = false
            self.live = self.storage
        }
    }
}
