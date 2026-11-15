import Foundation

public struct RemoteBreadcrumb: Sendable, Hashable, Identifiable {
    public let name: String
    public let path: String
    public var id: String { path }
}

extension RemotePath {
    /// Root first, then each folder down to `path`
    public static func breadcrumbs(of path: String) -> [RemoteBreadcrumb] {
        var crumbs = [RemoteBreadcrumb(name: "/", path: "/")]
        var current = "/"
        for part in path.split(separator: "/") {
            current = join(current, String(part))
            crumbs.append(RemoteBreadcrumb(name: String(part), path: current))
        }
        return crumbs
    }

    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }
}

extension RemoteFileEntry {
    public enum PreviewKind: Sendable, Equatable {
        case image
        case text
        case none
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tiff"]
    private static let textExtensions: Set<String> = [
        "txt", "md", "log", "conf", "cfg", "ini", "json", "yml", "yaml", "toml", "xml", "csv",
        "sh", "env", "service", "py", "rs", "swift", "kt", "js", "html", "css", "sql", "list", "pem",
    ]
    public static let thumbnailLimit: UInt64 = 2 * 1024 * 1024

    public var previewKind: PreviewKind {
        guard kind == .file || kind == .symlink else { return .none }
        let ext = (name as NSString).pathExtension.lowercased()
        if Self.imageExtensions.contains(ext) { return .image }
        if Self.textExtensions.contains(ext) || (ext.isEmpty && name.hasPrefix(".")) { return .text }
        return .none
    }

    public var canThumbnail: Bool {
        previewKind == .image && (size ?? 0) <= Self.thumbnailLimit
    }
}

public enum BatchRename {
    public struct Change: Sendable, Equatable {
        public let oldName: String
        public let newName: String
    }

    /// Names that change, left out when empty, invalid, or clashing
    public static func plan(names: [String], existing: Set<String>, find: String,
                            replace: String) -> [Change] {
        guard !find.isEmpty else { return [] }
        var taken = existing
        var changes: [Change] = []
        for name in names {
            let renamed = name.replacingOccurrences(of: find, with: replace)
            guard renamed != name, RemotePath.isValidName(renamed), !taken.contains(renamed) else { continue }
            taken.remove(name)
            taken.insert(renamed)
            changes.append(Change(oldName: name, newName: renamed))
        }
        return changes
    }
}

public enum FileSearch {
    public static let defaultLimit = 500
    static let directoryBudget = 4000

    public static func matches(_ name: String, pattern: String) -> Bool {
        let needle = pattern.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return false }
        guard needle.contains("*") || needle.contains("?") else {
            return name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        let escaped = NSRegularExpression.escapedPattern(for: needle)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        return name.range(of: "^\(escaped)$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Breadth-first by name; stops at `limit` or on cancellation
    public static func walk(_ root: String, matching pattern: String, limit: Int,
                            list: (String) async throws -> [RemoteFileEntry]) async throws -> [RemoteFileEntry] {
        var found: [RemoteFileEntry] = []
        var queue = [root]
        var visited = 0
        while !queue.isEmpty, found.count < limit, visited < directoryBudget {
            try Task.checkCancellation()
            let directory = queue.removeFirst()
            visited += 1
            guard let entries = try? await list(directory) else { continue }
            for entry in entries {
                if matches(entry.name, pattern: pattern) {
                    found.append(entry)
                    if found.count >= limit { break }
                }
                if entry.kind == .directory { queue.append(entry.path) }
            }
        }
        return found
    }
}

public struct FileShortcuts: Codable, Sendable, Equatable {
    public static let recentLimit = 20

    public private(set) var bookmarks: [String] = []
    public private(set) var recents: [String] = []

    public init() {}

    public func isBookmarked(_ path: String) -> Bool { bookmarks.contains(path) }

    public mutating func toggleBookmark(_ path: String) {
        if let index = bookmarks.firstIndex(of: path) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.append(path)
        }
    }

    public mutating func noteOpened(_ path: String) {
        recents.removeAll { $0 == path }
        recents.insert(path, at: 0)
        if recents.count > Self.recentLimit { recents.removeLast(recents.count - Self.recentLimit) }
    }

    public mutating func renamed(_ oldPath: String, to newPath: String) {
        bookmarks = bookmarks.map { $0 == oldPath ? newPath : $0 }
        recents = recents.map { $0 == oldPath ? newPath : $0 }
    }

    public mutating func forget(_ path: String) {
        bookmarks.removeAll { $0 == path }
        recents.removeAll { $0 == path }
    }
}
