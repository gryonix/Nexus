import Combine
import Foundation
import gryonixNexusCore
import ServerControl

/// Keeps install sessions alive across navigation
@MainActor
final class InstallSessionRegistry: ObservableObject {
    static let shared = InstallSessionRegistry()

    /// Deployments whose session is actively installing
    @Published private(set) var installing: [Deployment] = []

    private var sessions: [UUID: InstallViewModel] = [:]

    private init() {}

    func existingSession(for id: UUID) -> InstallViewModel? {
        sessions[id]
    }

    func refreshActivity() {
        installing = sessions.values
            .filter { $0.isInstalling }
            .map(\.deployment)
        #if DEBUG
        InstallResetProbe.note("InstallSessionRegistry.refreshActivity() — installing.count=\(installing.count)", trace: true)
        #endif
        for session in sessions.values {
            if session.isInstalling {
                putOnLockScreen(session)
            } else {
                takeOffLockScreen(session)
            }
        }
    }

    /// The live session for this deployment, created on first use
    func session(for deployment: Deployment, bundle: GeneratedBundle) -> InstallViewModel {
        let fingerprint = InstallViewModel.fingerprint(of: bundle)
        if let existing = sessions[deployment.id],
           existing.isInstalling || existing.bundleFingerprint == fingerprint {
            return existing
        }
        let vm = InstallViewModel(deployment: deployment, bundle: bundle)
        sessions[deployment.id] = vm
        return vm
    }

    func resetIdleSession(for deploymentID: UUID) {
        guard let existing = sessions[deploymentID], !existing.isInstalling else { return }
        sessions[deploymentID] = nil
    }

    // MARK: - The lock screen

    /// One subscription per running install, dropped when it ends
    private var lockScreenWatchers: [UUID: Set<AnyCancellable>] = [:]

    /// How often the card may be redrawn
    private static let lockScreenUpdateSeconds: Double = 2

    private func putOnLockScreen(_ session: InstallViewModel) {
        let id = session.deployment.id
        guard lockScreenWatchers[id] == nil else { return }
        OperationActivities.shared.start(id: id,
                                         title: UIL10n.string("Installing the server"),
                                         serverName: session.deployment.name,
                                         progressText: session.lockScreenLine,
                                         progress: session.overallProgress,
                                         deploymentID: id,
                                         canStop: true)

        var watchers: Set<AnyCancellable> = []
        session.objectWillChange
            .throttle(for: .seconds(Self.lockScreenUpdateSeconds),
                      scheduler: DispatchQueue.main, latest: true)
            .sink { [weak session] _ in
                guard let session, session.isInstalling else { return }
                OperationActivities.shared.update(id: id,
                                                  progressText: session.lockScreenLine,
                                                  progress: session.overallProgress)
            }
            .store(in: &watchers)
        lockScreenWatchers[id] = watchers
    }

    private func takeOffLockScreen(_ session: InstallViewModel) {
        let id = session.deployment.id
        guard lockScreenWatchers.removeValue(forKey: id) != nil else { return }
        OperationActivities.shared.end(id: id,
                                       progressText: session.lockScreenLine,
                                       errorMessage: session.failureMessage)
    }
}

enum InstallAddressStore {
    private static let addressPrefix = "install-home-address-"
    private static let userPrefix = "install-user-"

    static func homeAddress(deploymentID: UUID) -> String {
        UserDefaults.standard.string(forKey: addressPrefix + deploymentID.uuidString) ?? ""
    }

    static func save(homeAddress: String, deploymentID: UUID) {
        save(homeAddress, forKey: addressPrefix + deploymentID.uuidString)
    }

    static func installUser(deploymentID: UUID, host: SSHHostID) -> String? {
        UserDefaults.standard.string(forKey: userKey(deploymentID, host))
    }

    static func save(installUser: String, deploymentID: UUID, host: SSHHostID) {
        save(installUser, forKey: userKey(deploymentID, host))
    }

    static func machineName(_ host: SSHHostID) -> String {
        switch host.kind {
        case .slot(let slot): return slot.rawValue
        case .node(let id): return id.uuidString
        }
    }

    /// Strictly the inverse
    static func machine(named name: String) -> SSHHostID? {
        switch name {
        case "home": return .home
        case "vps": return .vps
        default: return UUID(uuidString: name).map { .node($0) }
        }
    }

    static func forget(deploymentID: UUID, nodeIDs: [UUID]) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: addressPrefix + deploymentID.uuidString)
        for host in [SSHHostID.vps, .home] + nodeIDs.map({ SSHHostID.node($0) }) {
            defaults.removeObject(forKey: userKey(deploymentID, host))
        }
    }

    private static func userKey(_ id: UUID, _ host: SSHHostID) -> String {
        userPrefix + machineName(host) + "-" + id.uuidString
    }

    private static func save(_ value: String, forKey key: String) {
        if value.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(value, forKey: key)
        }
    }
}

extension Notification.Name {
    static let gryonixDeploymentInstalled = Notification.Name("gryonixDeploymentInstalled")
}
