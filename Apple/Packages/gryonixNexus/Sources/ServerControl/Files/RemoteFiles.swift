import Foundation

public struct RemoteFileEntry: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case file
        case directory
        case symlink
        case other
    }

    public let name: String
    public let path: String
    public let kind: Kind
    public let size: UInt64?
    public let modified: Date?

    public var id: String { path }

    public init(name: String, path: String, kind: Kind, size: UInt64? = nil, modified: Date? = nil) {
        self.name = name
        self.path = path
        self.kind = kind
        self.size = size
        self.modified = modified
    }

    /// POSIX file-type bits (S_IFMT) from the SFTP permissions word
    public static func kind(fromPermissions permissions: UInt32?) -> Kind {
        guard let permissions else { return .other }
        switch permissions & 0o170000 {
        case 0o040000: return .directory
        case 0o120000: return .symlink
        case 0o100000: return .file
        default: return .other
        }
    }

    public static func sorted(_ entries: [RemoteFileEntry]) -> [RemoteFileEntry] {
        entries.sorted { lhs, rhs in
            let lhsDir = lhs.kind == .directory
            let rhsDir = rhs.kind == .directory
            if lhsDir != rhsDir { return lhsDir }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

public enum RemotePath {
    public static func join(_ directory: String, _ name: String) -> String {
        directory == "/" ? "/\(name)" : "\(directory)/\(name)"
    }

    public static func parent(of path: String) -> String {
        guard path != "/", let index = path.lastIndex(of: "/") else { return "/" }
        let parent = String(path[..<index])
        return parent.isEmpty ? "/" : parent
    }

    public static func name(of path: String) -> String {
        guard let index = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: index)...])
    }
}

/// SFTP file access to a deployment's hosts
public protocol RemoteFileBrowser: Sendable {
    /// The login user's home directory — the browser's landing path
    func homeDirectory(on host: SSHHostID) async throws -> String
    func listDirectory(_ path: String, on host: SSHHostID) async throws -> [RemoteFileEntry]
    func downloadFile(_ path: String, on host: SSHHostID, maxBytes: UInt64) async throws -> Data
    func uploadFile(_ data: Data, to path: String, on host: SSHHostID) async throws
    func deleteFile(_ entry: RemoteFileEntry, on host: SSHHostID) async throws
}
