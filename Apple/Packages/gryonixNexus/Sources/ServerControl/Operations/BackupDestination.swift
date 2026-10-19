import Foundation

public struct BackupDestinationSettings: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
        case none
        /// Another host over SSH, with a key this server owns
        case ssh
        /// Any S3-compatible bucket, through rclone on the server
        case s3
    }

    public var kind: Kind
    /// ssh/sftp: the host
    public var host: String
    public var port: Int
    public var user: String
    public var path: String
    public var bucket: String
    /// How many copies to keep ON THE DESTINATION
    public var keep: Int

    public init(kind: Kind = .none, host: String = "", port: Int = 22, user: String = "",
                path: String = "", bucket: String = "", keep: Int = 0) {
        self.kind = kind
        self.host = host
        self.port = port
        self.user = user
        self.path = path
        self.bucket = bucket
        self.keep = keep
    }

    /// Whether this says enough to copy anything anywhere
    public var isConfigured: Bool {
        switch kind {
        case .none: return false
        case .ssh: return !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !user.trimmingCharacters(in: .whitespaces).isEmpty
        case .s3: return !bucket.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}

public struct BackupDestinationState: Sendable, Hashable {
    public var settings: BackupDestinationSettings
    public var publicKey: String
    public var lastShipment: Date?
    public var lastShipmentSucceeded: Bool
    /// The far side's own words
    public var lastError: String

    public init(settings: BackupDestinationSettings = BackupDestinationSettings(),
                publicKey: String = "", lastShipment: Date? = nil,
                lastShipmentSucceeded: Bool = false, lastError: String = "") {
        self.settings = settings
        self.publicKey = publicKey
        self.lastShipment = lastShipment
        self.lastShipmentSucceeded = lastShipmentSucceeded
        self.lastError = lastError
    }
}

/// What a check of the destination came back with
public struct BackupDestinationTestResult: Sendable, Hashable {
    public var succeeded: Bool
    public var detail: String

    public init(succeeded: Bool, detail: String = "") {
        self.succeeded = succeeded
        self.detail = detail
    }
}

/// Parsing of what the wrapper's `show-destination` prints
public enum BackupDestinationParsing {
    public static func parse(_ output: String) -> BackupDestinationState {
        var state = BackupDestinationState()
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
            switch parts[0].trimmingCharacters(in: .whitespaces) {
            case "DEST_KIND":
                state.settings.kind = BackupDestinationSettings.Kind(rawValue: value) ?? .none
            case "DEST_HOST": state.settings.host = value
            case "DEST_PORT": state.settings.port = Int(value) ?? 22
            case "DEST_USER": state.settings.user = value
            case "DEST_PATH": state.settings.path = value
            case "DEST_BUCKET": state.settings.bucket = value
            case "DEST_KEEP": state.settings.keep = Int(value) ?? 0
            case "DEST_PUBKEY": state.publicKey = value
            case "AT":
                if let seconds = TimeInterval(value), seconds > 0 {
                    state.lastShipment = Date(timeIntervalSince1970: seconds)
                }
            case "OK": state.lastShipmentSucceeded = value == "1"
            case "ERROR": state.lastError = value
            default: continue
            }
        }
        return state
    }
}
