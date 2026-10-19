import Foundation
import ServerControl
import ServiceCatalog

@MainActor
final class PendingAgentInstalls: ObservableObject {
    static let shared = PendingAgentInstalls()

    struct Pending: Identifiable, Equatable {
        let deploymentID: UUID
        let serviceID: ServiceID
        /// What to call it on screen
        let serviceName: String
        let serverName: String
        let startedAt: Date

        var id: String { "\(deploymentID.uuidString)-\(serviceID.rawValue)" }
    }

    @Published private(set) var pending: [Pending] = []

    private let store: InstallJobStore
    /// Where the server names come from
    private let fleet: any DeploymentStore

    init(store: InstallJobStore = InstallJobStore(),
         fleet: any DeploymentStore = FileDeploymentStore()) {
        self.store = store
        self.fleet = fleet
        refresh()
    }

    /// Re-read the record
    func refresh() {
        let names = (try? fleet.load())?.reduce(into: [UUID: String]()) { $0[$1.id] = $1.name } ?? [:]
        pending = store.load()
            .map { job in
                let service = ServiceID(rawValue: job.serviceID)
                return Pending(
                    deploymentID: job.deploymentID,
                    serviceID: service,
                    serviceName: ServiceRegistry.service(service)?.displayName ?? job.serviceID,
                    serverName: names[job.deploymentID] ?? "",
                    startedAt: job.startedAt)
            }
            .sorted { $0.startedAt < $1.startedAt }
        syncLockScreen()
    }

    func isPending(deployment: UUID, service: ServiceID) -> Bool {
        pending.contains { $0.deploymentID == deployment && $0.serviceID == service }
    }

    // MARK: - The lock screen

    /// The card each record has, by the record's id
    private var cards: [String: UUID] = [:]

    private func syncLockScreen() {
        let live = Set(pending.map(\.id))
        for (recordID, cardID) in cards where !live.contains(recordID) {
            cards[recordID] = nil
            OperationActivities.shared.end(id: cardID, progressText: "", errorMessage: nil)
        }
        for row in pending where cards[row.id] == nil {
            guard !isWatchedLive(row) else { continue }
            let cardID = UUID()
            cards[row.id] = cardID
            OperationActivities.shared.start(
                id: cardID,
                title: UIL10n.string("Installing %@…", row.serviceName),
                serverName: row.serverName,
                progressText: UIL10n.string("Running on the server. Open to watch it."))
        }
    }

    /// Another card already shows this install
    private func isWatchedLive(_ row: Pending) -> Bool {
        if InstallSessionRegistry.shared.existingSession(for: row.deploymentID)?.isInstalling == true {
            return true
        }
        return RunningOperationsRegistry.shared.entries.contains {
            $0.state.title.contains(row.serviceName)
        }
    }

    /// The live run takes the card over
    func yieldLockScreen(matching title: String) {
        for row in pending where title.contains(row.serviceName) {
            guard let cardID = cards.removeValue(forKey: row.id) else { continue }
            OperationActivities.shared.end(id: cardID, progressText: "", errorMessage: nil)
        }
    }
}
