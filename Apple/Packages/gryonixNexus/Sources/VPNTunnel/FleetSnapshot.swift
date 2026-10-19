import Foundation
import ServiceCatalog

public struct FleetSnapshot: Codable, Sendable, Equatable {
    /// When the app last had these facts in hand
    public var generatedAt: Date
    public var servers: [Server]
    public var tunnel: TunnelSnapshot

    public init(generatedAt: Date = Date(), servers: [Server] = [], tunnel: TunnelSnapshot = .off) {
        self.generatedAt = generatedAt
        self.servers = servers
        self.tunnel = tunnel
    }

    public struct Server: Codable, Sendable, Equatable, Identifiable {
        public let id: UUID
        public var name: String
        public var protocols: [ProtocolDevices]
        /// Set when the last reading failed
        public var failure: String?
        public var metrics: Reading?
        public var services: ServicesSummary?
        public var security: SecuritySummary?
        /// Whether unattended backups are armed, and over how much
        public var backups: BackupsSummary?
        /// How many services have something to pull
        public var updates: UpdatesSummary?

        public init(id: UUID, name: String, protocols: [ProtocolDevices] = [],
                    failure: String? = nil, metrics: Reading? = nil,
                    services: ServicesSummary? = nil, security: SecuritySummary? = nil,
                    backups: BackupsSummary? = nil, updates: UpdatesSummary? = nil) {
            self.id = id
            self.name = name
            self.protocols = protocols
            self.failure = failure
            self.metrics = metrics
            self.services = services
            self.security = security
            self.backups = backups
            self.updates = updates
        }

        public var hasAnyReading: Bool {
            metrics != nil || services != nil || security != nil
                || backups != nil || updates != nil || !protocols.isEmpty
        }

        public var deviceCount: Int { protocols.reduce(0) { $0 + $1.deviceCount } }

        /// "WireGuard · OpenVPN" — the protocols that actually hold devices
        public var protocolSummary: String {
            protocols.filter { $0.deviceCount > 0 }
                .map(\.protocolID.displayName)
                .joined(separator: " · ")
        }
    }

    public struct Reading: Codable, Sendable, Equatable {
        /// 0...100, or nil when two samples did not exist yet
        public var cpuPercent: Double?
        public var memUsedBytes: Int64
        public var memTotalBytes: Int64
        public var diskUsedBytes: Int64
        public var diskTotalBytes: Int64
        /// Which machine of the deployment this is
        public var machineLabel: String
        public var takenAt: Date

        public init(cpuPercent: Double?, memUsedBytes: Int64, memTotalBytes: Int64,
                    diskUsedBytes: Int64, diskTotalBytes: Int64,
                    machineLabel: String, takenAt: Date) {
            self.cpuPercent = cpuPercent
            self.memUsedBytes = memUsedBytes
            self.memTotalBytes = memTotalBytes
            self.diskUsedBytes = diskUsedBytes
            self.diskTotalBytes = diskTotalBytes
            self.machineLabel = machineLabel
            self.takenAt = takenAt
        }

        public var memoryPercent: Double? {
            memTotalBytes > 0 ? Double(memUsedBytes) / Double(memTotalBytes) * 100 : nil
        }

        public var diskPercent: Double? {
            diskTotalBytes > 0 ? Double(diskUsedBytes) / Double(diskTotalBytes) * 100 : nil
        }

        public var age: TimeInterval { Date().timeIntervalSince(takenAt) }
    }

    public struct ServicesSummary: Codable, Sendable, Equatable {
        public var total: Int
        /// Services with at least one container that is not healthy
        public var needingAttention: Int
        public var takenAt: Date

        public init(total: Int, needingAttention: Int, takenAt: Date) {
            self.total = total
            self.needingAttention = needingAttention
            self.takenAt = takenAt
        }

        public var allWell: Bool { needingAttention == 0 && total > 0 }
        public var age: TimeInterval { Date().timeIntervalSince(takenAt) }
    }

    public struct SecuritySummary: Codable, Sendable, Equatable {
        /// CrowdSec installed at all
        public var isPresent: Bool
        public var engineRunning: Bool
        public var bouncerRunning: Bool
        public var alertsLast24h: Int
        public var localBans: Int
        public var communityBlocklistIPs: Int
        public var takenAt: Date

        public init(isPresent: Bool, engineRunning: Bool, bouncerRunning: Bool,
                    alertsLast24h: Int, localBans: Int, communityBlocklistIPs: Int,
                    takenAt: Date) {
            self.isPresent = isPresent
            self.engineRunning = engineRunning
            self.bouncerRunning = bouncerRunning
            self.alertsLast24h = alertsLast24h
            self.localBans = localBans
            self.communityBlocklistIPs = communityBlocklistIPs
            self.takenAt = takenAt
        }

        public var isGuarding: Bool { isPresent && engineRunning && bouncerRunning }
        public var age: TimeInterval { Date().timeIntervalSince(takenAt) }
    }

    public struct BackupsSummary: Codable, Sendable, Equatable {
        public var isOn: Bool
        public var everyHours: Int?
        public var everyDays: Int?
        public var servicesCovered: Int
        public var retention: Int
        public var takenAt: Date

        public init(isOn: Bool, everyHours: Int? = nil, everyDays: Int? = nil,
                    servicesCovered: Int, retention: Int, takenAt: Date) {
            self.isOn = isOn
            self.everyHours = everyHours
            self.everyDays = everyDays
            self.servicesCovered = servicesCovered
            self.retention = retention
            self.takenAt = takenAt
        }

        public var age: TimeInterval { Date().timeIntervalSince(takenAt) }
    }

    /// How many services have something to pull
    public struct UpdatesSummary: Codable, Sendable, Equatable {
        public var waiting: Int
        public var checked: Int
        public var lastRunOnServer: Date?
        public var takenAt: Date

        public init(waiting: Int, checked: Int, lastRunOnServer: Date?, takenAt: Date) {
            self.waiting = waiting
            self.checked = checked
            self.lastRunOnServer = lastRunOnServer
            self.takenAt = takenAt
        }

        public var age: TimeInterval { Date().timeIntervalSince(takenAt) }
    }

    public struct ProtocolDevices: Codable, Sendable, Equatable, Identifiable {
        public let protocolID: ServiceID
        public var deviceCount: Int
        /// A few names, for the large widget
        public var deviceNames: [String]

        public var id: String { protocolID.rawValue }

        public init(protocolID: ServiceID, deviceCount: Int, deviceNames: [String] = []) {
            self.protocolID = protocolID
            self.deviceCount = deviceCount
            self.deviceNames = deviceNames
        }
    }

    public var deviceCount: Int { servers.reduce(0) { $0 + $1.deviceCount } }
    public var reachableServerCount: Int { servers.filter { $0.failure == nil }.count }

    // MARK: - The fleet at a glance

    public var serversWithServiceReadings: [Server] { servers.filter { $0.services != nil } }

    public var totalServices: Int {
        serversWithServiceReadings.reduce(0) { $0 + ($1.services?.total ?? 0) }
    }

    public var servicesNeedingAttention: Int {
        serversWithServiceReadings.reduce(0) { $0 + ($1.services?.needingAttention ?? 0) }
    }

    /// Machines whose last reading failed
    public var unreachableServerCount: Int { servers.filter { $0.failure != nil }.count }

    public var oldestReadingAge: TimeInterval? {
        let dates = servers.compactMap { server -> Date? in
            [server.metrics?.takenAt, server.services?.takenAt,
             server.security?.takenAt, server.backups?.takenAt,
             server.updates?.takenAt].compactMap { $0 }.max()
        }
        guard let oldest = dates.min() else { return nil }
        return Date().timeIntervalSince(oldest)
    }

    /// How old this reading is, right now
    public var age: TimeInterval { Date().timeIntervalSince(generatedAt) }

    /// Has the app never written one?
    public var isEmpty: Bool { servers.isEmpty && tunnel.status == .off && tunnel.profileName == nil }
}

public struct TunnelSnapshot: Codable, Sendable, Equatable {
    public var status: TunnelStatus
    public var profileID: UUID?
    public var profileName: String?
    public var serverName: String?
    public var protocolName: String?
    public var statistics: TunnelStatistics
    public var isSimulated: Bool
    public var profileCount: Int

    public static let off = TunnelSnapshot(status: .off, isSimulated: !TunnelAvailability.carriesTraffic)

    public init(status: TunnelStatus,
                profileID: UUID? = nil,
                profileName: String? = nil,
                serverName: String? = nil,
                protocolName: String? = nil,
                statistics: TunnelStatistics = .zero,
                isSimulated: Bool,
                profileCount: Int = 0) {
        self.status = status
        self.profileID = profileID
        self.profileName = profileName
        self.serverName = serverName
        self.protocolName = protocolName
        self.statistics = statistics
        self.isSimulated = isSimulated
        self.profileCount = profileCount
    }

    public var subtitle: String? {
        let parts = [serverName, protocolName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

public struct FleetSnapshotStore: Sendable {
    private let file: SharedJSONFile<FleetSnapshot>

    public init() {
        self.file = SharedJSONFile(name: "fleet-snapshot.json")
    }

    public init(fileURL: URL) {
        self.file = SharedJSONFile(url: fileURL)
    }

    public func read() -> FleetSnapshot? { file.read() }

    @discardableResult
    public func write(_ snapshot: FleetSnapshot) -> Bool { file.write(snapshot) }

    @discardableResult
    public func writeTunnel(_ tunnel: TunnelSnapshot) -> Bool {
        var snapshot = file.read() ?? FleetSnapshot()
        snapshot.tunnel = tunnel
        return file.write(snapshot)
    }

    @discardableResult
    public func writeServers(_ servers: [FleetSnapshot.Server], at date: Date = Date()) -> Bool {
        var snapshot = file.read() ?? FleetSnapshot()
        snapshot.servers = servers
        snapshot.generatedAt = date
        return file.write(snapshot)
    }

    /// One server's reading, merged into whatever is already on disk
    @discardableResult
    public func updateServer(id: UUID, name: String, at date: Date = Date(),
                             _ change: (inout FleetSnapshot.Server) -> Void) -> Bool {
        var snapshot = file.read() ?? FleetSnapshot()
        if let index = snapshot.servers.firstIndex(where: { $0.id == id }) {
            snapshot.servers[index].name = name
            change(&snapshot.servers[index])
        } else {
            var server = FleetSnapshot.Server(id: id, name: name)
            change(&server)
            snapshot.servers.append(server)
        }
        snapshot.generatedAt = date
        return file.write(snapshot)
    }

    @discardableResult
    public func upsertMetrics(id: UUID, name: String,
                              reading: FleetSnapshot.Reading,
                              at date: Date = Date()) -> Bool {
        updateServer(id: id, name: name, at: date) { $0.metrics = reading }
    }

    @discardableResult
    public func upsertServices(id: UUID, name: String,
                               summary: FleetSnapshot.ServicesSummary,
                               at date: Date = Date()) -> Bool {
        updateServer(id: id, name: name, at: date) { $0.services = summary }
    }

    @discardableResult
    public func upsertSecurity(id: UUID, name: String,
                               summary: FleetSnapshot.SecuritySummary,
                               at date: Date = Date()) -> Bool {
        updateServer(id: id, name: name, at: date) { $0.security = summary }
    }

    @discardableResult
    public func upsertBackups(id: UUID, name: String,
                              summary: FleetSnapshot.BackupsSummary,
                              at date: Date = Date()) -> Bool {
        updateServer(id: id, name: name, at: date) { $0.backups = summary }
    }

    @discardableResult
    public func upsertUpdates(id: UUID, name: String,
                              summary: FleetSnapshot.UpdatesSummary,
                              at date: Date = Date()) -> Bool {
        updateServer(id: id, name: name, at: date) { $0.updates = summary }
    }

    @discardableResult
    public func upsertServer(id: UUID,
                             name: String,
                             protocols: [FleetSnapshot.ProtocolDevices],
                             failure: String?,
                             at date: Date = Date()) -> Bool {
        var snapshot = file.read() ?? FleetSnapshot()
        var server = snapshot.servers.first { $0.id == id }
            ?? FleetSnapshot.Server(id: id, name: name)
        server.name = name
        server.failure = failure
        for reading in protocols {
            if let existing = server.protocols.firstIndex(where: { $0.protocolID == reading.protocolID }) {
                server.protocols[existing] = reading
            } else {
                server.protocols.append(reading)
            }
        }
        server.protocols.sort { $0.protocolID.rawValue < $1.protocolID.rawValue }

        if let index = snapshot.servers.firstIndex(where: { $0.id == id }) {
            snapshot.servers[index] = server
        } else {
            snapshot.servers.append(server)
        }
        snapshot.generatedAt = date
        return file.write(snapshot)
    }

    @discardableResult
    public func forgetServer(id: UUID) -> Bool {
        guard var snapshot = file.read() else { return false }
        let before = snapshot.servers.count
        snapshot.servers.removeAll { $0.id == id }
        guard snapshot.servers.count != before else { return false }
        return file.write(snapshot)
    }
}

public enum AppLink {
    public static let scheme = "gryonixnexus"

    public enum Destination: Equatable, Sendable {
        /// The devices of one server
        case server(UUID)
        /// The tunnel card
        case tunnel
        /// Bring the app forward, nothing more
        case app
        /// One long operation's sheet
        case operation(UUID)
        /// A server job, by its agent id
        case job(String)
    }

    public static func url(for destination: Destination) -> URL {
        switch destination {
        case .server(let id): return URL(string: "\(scheme)://server/\(id.uuidString)")!
        case .tunnel: return URL(string: "\(scheme)://tunnel")!
        case .app: return URL(string: "\(scheme)://open")!
        case .operation(let id): return URL(string: "\(scheme)://operation/\(id.uuidString)")!
        case .job(let id): return URL(string: "\(scheme)://job/\(id)")!
        }
    }

    public static func destination(of url: URL) -> Destination? {
        guard url.scheme?.caseInsensitiveCompare(scheme) == .orderedSame else { return nil }
        switch url.host() {
        case "server":
            let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return UUID(uuidString: raw).map(Destination.server)
        case "tunnel": return .tunnel
        case "open": return .app
        case "operation":
            let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return UUID(uuidString: raw).map(Destination.operation)
        case "job":
            let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return raw.isEmpty ? nil : .job(raw)
        default: return nil
        }
    }
}
