import Foundation
import ServerControl

/// Bookmarks and recent files per server, kept on this device
struct FileShortcutsStore {
    let defaults: UserDefaults
    let deploymentID: UUID

    init(deploymentID: UUID, defaults: UserDefaults = .standard) {
        self.deploymentID = deploymentID
        self.defaults = defaults
    }

    private var key: String { "files.shortcuts.\(deploymentID.uuidString)" }

    func load() -> FileShortcuts {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(FileShortcuts.self, from: data) else { return FileShortcuts() }
        return value
    }

    func save(_ shortcuts: FileShortcuts) {
        defaults.set(try? JSONEncoder().encode(shortcuts), forKey: key)
    }
}

/// Small image downloads kept for the list
actor FileThumbnailCache {
    static let shared = FileThumbnailCache()
    private var cache: [String: Data] = [:]

    func data(for key: String) -> Data? { cache[key] }

    func store(_ data: Data, for key: String) {
        if cache.count > 200 { cache.removeAll() }
        cache[key] = data
    }
}
