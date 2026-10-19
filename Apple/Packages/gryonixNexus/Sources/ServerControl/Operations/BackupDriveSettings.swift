import Foundation

/// Which USB drives take a copy, and how
public struct BackupDriveSettings: Sendable, Hashable {
    public enum Mode: String, Sendable, Hashable, CaseIterable {
        /// This server and every drive
        case both
        /// This server only
        case local
        /// The drives only
        case drive
    }

    public var mode: Mode
    /// Encrypt copies on the drives
    public var encrypt: Bool
    /// Filesystem UUIDs of the drives in use
    public var uuids: [String]

    public init(mode: Mode = .both, encrypt: Bool = true, uuids: [String] = []) {
        self.mode = mode
        self.encrypt = encrypt
        self.uuids = uuids
    }
}

/// One chosen drive, as the server sees it now
public struct BackupDriveStatus: Sendable, Hashable {
    public var uuid: String
    public var mounted: Bool
    public var sizeBytes: Int64
    public var freeBytes: Int64
    public var mountPoint: String

    public init(uuid: String, mounted: Bool = false, sizeBytes: Int64 = 0, freeBytes: Int64 = 0,
                mountPoint: String = "") {
        self.uuid = uuid
        self.mounted = mounted
        self.sizeBytes = sizeBytes
        self.freeBytes = freeBytes
        self.mountPoint = mountPoint
    }

    /// The drive's name: the last part of its mount point
    public var name: String {
        mountPoint.split(separator: "/").last.map(String.init) ?? uuid
    }
}

/// Drive settings, drives and the last copy, read back
public struct BackupDrivesState: Sendable, Hashable {
    public var settings: BackupDriveSettings
    public var statuses: [BackupDriveStatus]
    public var lastCopy: Date?
    public var lastCopySucceeded: Bool
    public var lastError: String
    public var hasPassphrase: Bool
    /// False when the server's wrapper predates USB drives
    public var supported: Bool

    public init(settings: BackupDriveSettings = BackupDriveSettings(), statuses: [BackupDriveStatus] = [],
                lastCopy: Date? = nil, lastCopySucceeded: Bool = false, lastError: String = "",
                hasPassphrase: Bool = false, supported: Bool = true) {
        self.settings = settings
        self.statuses = statuses
        self.lastCopy = lastCopy
        self.lastCopySucceeded = lastCopySucceeded
        self.lastError = lastError
        self.hasPassphrase = hasPassphrase
        self.supported = supported
    }

    /// Drive names by UUID, for unplugged drives
    public var namesByUUID: [String: String] {
        Dictionary(statuses.map { ($0.uuid, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// Settings with a newly formatted drive replacing its predecessors
    public func settings(formatted uuid: String, replacing old: String?, name: String) -> BackupDriveSettings {
        var settings = self.settings
        let names = namesByUUID
        settings.uuids.removeAll { $0 == uuid || $0 == old || names[$0] == name }
        settings.uuids.append(uuid)
        return settings
    }

    /// Whether the server keeps no mount point for this drive
    public func isUnmapped(_ uuid: String) -> Bool {
        statuses.first { $0.uuid == uuid }?.mountPoint.isEmpty ?? true
    }
}

/// Parsing of what the wrapper's `show-drives` prints
public enum BackupDrivesParsing {
    public static func parse(_ output: String) -> BackupDrivesState {
        var state = BackupDrivesState()
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            apply(key: parts[0].trimmingCharacters(in: .whitespaces),
                  value: parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\" ")), to: &state)
        }
        return state
    }

    private static func apply(key: String, value: String, to state: inout BackupDrivesState) {
        switch key {
        case "DRIVE_MODE": state.settings.mode = BackupDriveSettings.Mode(rawValue: value) ?? .both
        case "DRIVE_ENCRYPT": state.settings.encrypt = value != "0"
        case "DRIVES": state.settings.uuids = value.split(separator: " ").map(String.init)
        case "DRIVE_PASS": state.hasPassphrase = value == "1"
        case "DRIVE": if let status = status(value) { state.statuses.append(status) }
        case "DRIVE_AT":
            if let seconds = TimeInterval(value), seconds > 0 {
                state.lastCopy = Date(timeIntervalSince1970: seconds)
            }
        case "DRIVE_OK": state.lastCopySucceeded = value == "1"
        case "DRIVE_ERROR": state.lastError = value
        default: break
        }
    }

    /// `<uuid> <mounted> <size> <free> <mount point>`
    private static func status(_ value: String) -> BackupDriveStatus? {
        let fields = value.split(separator: " ", maxSplits: 4).map(String.init)
        guard fields.count >= 4 else { return nil }
        return BackupDriveStatus(uuid: fields[0], mounted: fields[1] == "1",
                                 sizeBytes: Int64(fields[2]) ?? 0, freeBytes: Int64(fields[3]) ?? 0,
                                 mountPoint: fields.count > 4 ? fields[4] : "")
    }
}
