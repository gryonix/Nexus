import Foundation

public enum AppSupportDirectory {
    /// Where this app keeps its files; tvOS allows only Caches
    public static var base: URL {
        #if os(tvOS)
        let kind = FileManager.SearchPathDirectory.cachesDirectory
        #else
        let kind = FileManager.SearchPathDirectory.applicationSupportDirectory
        #endif
        return FileManager.default.urls(for: kind, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    public static func adoptLegacyName(at directory: URL, legacyName: String) {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: directory.path) else { return }
        let legacy = directory.deletingLastPathComponent()
            .appendingPathComponent(legacyName, isDirectory: true)
        guard manager.fileExists(atPath: legacy.path) else { return }
        try? manager.moveItem(at: legacy, to: directory)
    }
}
