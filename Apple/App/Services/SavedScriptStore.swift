import Foundation
import ServerControl

/// Saved scripts, kept on this device only
@MainActor
final class SavedScriptStore: ObservableObject {
    static let shared = SavedScriptStore(cloud: nil)
    static let key = "scripts.v1"

    @Published private(set) var scripts: [SavedScript] = []
    private let local: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore?
    private var observer: NSObjectProtocol?

    init(local: UserDefaults = .standard, cloud: NSUbiquitousKeyValueStore? = .default) {
        self.local = local
        self.cloud = cloud
        scripts = Self.decode(local.data(forKey: Self.key))
        guard let cloud else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.adoptCloud() }
        }
        cloud.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func save(_ script: SavedScript) {
        persist(SavedScriptList.upserting(script, into: scripts))
    }

    func delete(_ script: SavedScript) {
        persist(SavedScriptList.removing(script.id, from: scripts))
    }

    private func persist(_ updated: [SavedScript]) {
        scripts = updated
        let data = try? JSONEncoder().encode(updated)
        local.set(data, forKey: Self.key)
        cloud?.set(data, forKey: Self.key)
    }

    private func adoptCloud() {
        guard let data = cloud?.data(forKey: Self.key) else { return }
        local.set(data, forKey: Self.key)
        scripts = Self.decode(data)
    }

    private static func decode(_ data: Data?) -> [SavedScript] {
        data.flatMap { try? JSONDecoder().decode([SavedScript].self, from: $0) } ?? []
    }
}
