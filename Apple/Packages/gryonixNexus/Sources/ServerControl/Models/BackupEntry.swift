import Foundation

/// One backup file from an `ls -lht` listing.
public struct BackupEntry: Sendable, Hashable {
    public let name: String
    /// Human size as printed by ls -h, e.g
    public let sizeText: String
    /// Modification date columns as printed by ls, e.g
    public let dateText: String
    /// mailcow stores each backup as a DIRECTORY
    public let isDirectory: Bool
    /// The USB drive holding this copy, if any
    public let drive: String?
    /// Exact size and time, when the source reports them
    public let sizeBytes: Int64?
    public let modifiedAt: Date?

    /// Name without the directory part — what lists and pickers show
    public var displayName: String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    public init(name: String, sizeText: String, dateText: String, isDirectory: Bool = false,
                drive: String? = nil, sizeBytes: Int64? = nil, modifiedAt: Date? = nil) {
        self.name = name
        self.sizeText = sizeText
        self.dateText = dateText
        self.isDirectory = isDirectory
        self.drive = drive
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
    }
}
