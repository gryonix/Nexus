import Foundation

public enum AppSupportDirectory {
    public static func adoptLegacyName(at directory: URL, legacyName: String) {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: directory.path) else { return }
        let legacy = directory.deletingLastPathComponent()
            .appendingPathComponent(legacyName, isDirectory: true)
        guard manager.fileExists(atPath: legacy.path) else { return }
        try? manager.moveItem(at: legacy, to: directory)
    }
}
