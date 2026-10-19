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

    private init() {}

    func controller(for profile: TerminalProfile, on deployment: Deployment) -> TerminalController {
        if let existing = storage[profile.id] { return existing }
        let controller = TerminalController(deployment: deployment, profile: profile)
        storage[profile.id] = controller
        publishSoon()
        return controller
    }

    func existing(for profile: TerminalProfile) -> TerminalController? {
        storage[profile.id]
    }

    func end(_ profile: TerminalProfile) {
        storage[profile.id]?.disconnect()
        storage[profile.id] = nil
        publishSoon()
    }

    func endAll(for deploymentID: UUID) {
        for (id, controller) in storage where controller.deployment.id == deploymentID {
            controller.disconnect()
            storage[id] = nil
        }
        publishSoon()
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
