import Foundation

public struct BackupEstimate: Sendable, Hashable {
    /// On-disk size of everything the run would archive, before compression
    public let dataBytes: UInt64
    /// Free space on the filesystem holding the backup directory
    public let freeBytes: UInt64

    public init(dataBytes: UInt64, freeBytes: UInt64) {
        self.dataBytes = dataBytes
        self.freeBytes = freeBytes
    }

    public init?(output: String) {
        guard let line = output.split(separator: "\n").first(where: {
            $0.hasPrefix(CommandCatalog.Backups.estimateMarker)
        }) else { return nil }
        let fields = line.split(separator: " ")
        guard fields.count >= 3, let data = UInt64(fields[1]), let free = UInt64(fields[2]) else {
            return nil
        }
        self.init(dataBytes: data, freeBytes: free)
    }

    public var fitsOnDisk: Bool { freeBytes > dataBytes }
}

/// The result of one wrapper-driven backup
public struct BackupOutcome: Sendable, Hashable {
    /// Size of the finished archive
    public let sizeBytes: UInt64?
    public let path: String?
    /// The streamed output, tailed for display
    public let log: String

    public init(sizeBytes: UInt64?, path: String?, log: String) {
        self.sizeBytes = sizeBytes
        self.path = path
        self.log = log
    }

    /// Reads the wrapper's `GRYONIXNEXUS_BACKUP_DONE <bytes> <path>` line
    public init?(output: String, log: String) {
        guard let line = output.split(separator: "\n").last(where: {
            $0.hasPrefix(CommandCatalog.Backups.backupDoneMarker)
        }) else { return nil }
        let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count == 3, let size = UInt64(fields[1]) else { return nil }
        self.init(sizeBytes: size,
                  path: String(fields[2]).trimmingCharacters(in: .whitespacesAndNewlines),
                  log: log)
    }
}
