public struct BackupWrapperSpec: Sendable {
    /// The one wrapper every wrapper-driven backup goes through
    public static let wrapperPath = "/opt/gryonixnexus-backup-ctl.sh"

    /// Service label passed to the wrapper
    public let wrapperTarget: String
    /// Directory the app lists backups from, and uploads into
    public let backupDir: String
    /// The whitelisted invocation the app sends
    public let run: ServiceCommand
    /// What the wrapper actually does for this service
    public let plan: BackupPlan

    public init(wrapperTarget: String, backupDir: String, run: ServiceCommand,
                plan: BackupPlan) {
        self.wrapperTarget = wrapperTarget
        self.backupDir = backupDir
        self.run = run
        self.plan = plan
    }

    public var encryptsByDefault: Bool { plan.encryptsByDefault }

    /// Paths whose on-disk size the estimate sums before a run
    public var sizePaths: [String] { plan.sizePaths }
}

/// The two shapes a wrapper-driven backup takes
public enum BackupPlan: Sendable, Hashable {
    case externalScript(path: String, sizePaths: [String])
    /// The wrapper builds the archive itself, from the description below
    case archive(ArchiveBackupPlan)

    public var encryptsByDefault: Bool {
        switch self {
        case .externalScript: return false
        case .archive(let plan): return plan.encryptsByDefault
        }
    }

    public var sizePaths: [String] {
        switch self {
        case .externalScript(_, let paths): return paths
        case .archive(let plan): return plan.sizePaths
        }
    }

    public var archive: ArchiveBackupPlan? {
        if case .archive(let plan) = self { return plan }
        return nil
    }
}

public struct ArchiveBackupPlan: Sendable, Hashable {
    /// Directory holding the dumps inside the archive
    public static let dumpDirectoryName = "gryonixnexus-db"

    /// Compose project the stop/start and `exec` commands address
    public let composeProject: String
    public let dataPath: String
    /// Databases dumped through their own client instead of archived
    public let databases: [BackupDatabase]
    public let quiesceServices: [String]
    /// GPG unless the caller says otherwise
    public let encryptsByDefault: Bool
    public let sizePaths: [String]
    public let excludes: [String]

    public init(composeProject: String, dataPath: String,
                databases: [BackupDatabase] = [], quiesceServices: [String] = [],
                encryptsByDefault: Bool, sizePaths: [String], excludes: [String] = []) {
        self.composeProject = composeProject
        self.dataPath = dataPath
        self.databases = databases
        self.quiesceServices = quiesceServices
        self.encryptsByDefault = encryptsByDefault
        self.sizePaths = sizePaths
        self.excludes = excludes
    }

    public var dataSlot: String {
        dataPath.split(separator: "/").last.map(String.init) ?? dataPath
    }

    public var dataParent: String {
        let trimmed = dataPath.hasSuffix("/") ? String(dataPath.dropLast()) : dataPath
        guard let slash = trimmed.lastIndex(of: "/"), slash != trimmed.startIndex else { return "/" }
        return String(trimmed[trimmed.startIndex..<slash])
    }
}

/// One database dumped through its own client
public struct BackupDatabase: Sendable, Hashable {
    public enum Engine: String, Sendable, Hashable {
        /// Dumped with `pg_dump`, loaded with `psql`
        case postgres
        case mysql
    }

    public let engine: Engine
    /// Compose service name of the database container
    public let service: String
    /// File name inside the archive's dump directory
    public let fileName: String
    /// Which database inside that engine to dump
    public let databaseName: String?

    public init(engine: Engine, service: String, fileName: String,
                databaseName: String? = nil) {
        self.engine = engine
        self.service = service
        self.fileName = fileName
        self.databaseName = databaseName
    }
}
