import CryptoKit
import Foundation
import ServerControl

extension Notification.Name {
    /// iCloud brought or removed servers
    static let cloudSyncChangedServers = Notification.Name("gryonixnexus.cloudSyncChangedServers")
}

/// Keeps servers and imported tunnels in step through iCloud Keychain
@MainActor
final class CloudSync: ObservableObject {
    static let shared = CloudSync()

    enum Status: Equatable {
        case idle
        case syncing
        case needsPassword
        case failed(String)
        case synced(Date)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var mode: CloudSyncMode

    private let items: any CloudItemStoring
    private let store: any DeploymentStore
    private let localKeys: KeychainStore
    private let defaults: UserDefaults
    private let tunnels: @MainActor () -> TunnelController?
    private var key: SymmetricKey?
    private var pending: Task<Void, Never>?
    private var running = false

    static let modeKey = "cloudSync.mode"
    static let marksKey = "cloudSync.marks"
    static let lockAccount = "lock"
    private static let keyAccount = "cloudsync-password-key"

    init(items: any CloudItemStoring = CloudKeychain(),
         store: any DeploymentStore = FileDeploymentStore(),
         localKeys: KeychainStore = KeychainStore(),
         defaults: UserDefaults = .standard,
         tunnels: (@MainActor () -> TunnelController?)? = nil) {
        self.items = items
        self.store = store
        self.localKeys = localKeys
        self.defaults = defaults
        self.tunnels = tunnels ?? { TunnelController.shared }
        mode = CloudSyncMode(rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .off
        key = ((try? localKeys.data(for: Self.keyAccount)) ?? nil).map { SymmetricKey(data: $0) }
    }

    func choose(_ mode: CloudSyncMode) {
        self.mode = mode
        defaults.set(mode.rawValue, forKey: Self.modeKey)
        guard mode.syncs else { return status = .idle }
        if mode.usesPassword, !keyFits(items.all()) { return status = .needsPassword }
        scheduleSync(after: 0)
    }

    /// Whether iCloud already holds a sync password
    var passwordExists: Bool { lock(in: items.all()) != nil }

    /// Opens the existing password, or sets the first one
    func enter(password: String) async throws {
        let existing = lock(in: items.all())
        if let existing {
            remember(try await Task.detached { try CloudSyncSeal.unlock(existing, password: password) }.value)
        } else {
            try await replacePassword(with: password)
        }
        scheduleSync(after: 0)
    }

    /// A new password; every item is sealed again with it
    func replacePassword(with password: String) async throws {
        let (lock, fresh) = try await Task.detached { try CloudSyncSeal.lock(password: password) }.value
        try items.set(JSONEncoder().encode(lock), for: Self.lockAccount)
        remember(fresh)
        saveMarks(loadMarks().mapValues { CloudSyncMark(hash: "", at: $0.at) })
    }

    /// Removes everything this app put in iCloud
    func eraseICloudCopy() {
        for account in items.all().keys { items.delete(account) }
        defaults.removeObject(forKey: Self.marksKey)
        status = .idle
    }

    func scheduleSync(after seconds: Double = 2) {
        guard mode.syncs else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    func sync() async {
        guard mode.syncs, !running else { return }
        running = true
        defer { running = false }
        status = .syncing
        let remote = items.all()
        if mode.usesPassword, !keyFits(remote) { return status = .needsPassword }
        let run = CloudSyncRun(mode: mode, key: keyFits(remote) ? key : nil, items: items, store: store,
                               remote: remote, marks: loadMarks())
        run.servers()
        if mode.includesKeys, let tunnels = tunnels() { await run.tunnels(tunnels) }
        saveMarks(run.marks)
        if run.changedServers { NotificationCenter.default.post(name: .cloudSyncChangedServers, object: nil) }
        status = run.locked > 0 ? .needsPassword : run.failure.map(Status.failed) ?? .synced(Date())
    }

    private func lock(in remote: [String: Data]) -> CloudSyncPasswordLock? {
        remote[Self.lockAccount].flatMap { try? JSONDecoder().decode(CloudSyncPasswordLock.self, from: $0) }
    }

    private func keyFits(_ remote: [String: Data]) -> Bool {
        guard let key, let lock = lock(in: remote) else { return false }
        return CloudSyncSeal.fits(key, lock)
    }

    private func remember(_ fresh: SymmetricKey) {
        key = fresh
        try? localKeys.set(fresh.withUnsafeBytes { Data($0) }, for: Self.keyAccount)
    }

    private func loadMarks() -> [String: CloudSyncMark] {
        defaults.data(forKey: Self.marksKey)
            .flatMap { try? JSONDecoder().decode([String: CloudSyncMark].self, from: $0) } ?? [:]
    }

    private func saveMarks(_ marks: [String: CloudSyncMark]) {
        defaults.set(try? JSONEncoder().encode(marks), forKey: Self.marksKey)
    }
}
