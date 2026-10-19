/// Everything a self-hosted service knows about itself — one description
/// drives the generator (what to install, which ports, which sudoers lines)
/// and the dashboard (which buttons to show, which commands they run).
public protocol ManagedService: Sendable {
    var id: ServiceID { get }
    var displayName: String { get }
    var systemImage: String { get }
    /// Which shelf of the catalog this service sits on
    var category: ServiceCategory { get }
    /// Which shelf this service's ROW groups under on screen
    var displayCategory: ServiceCategory { get }
    /// Services that cannot coexist with this one (e.g
    var conflicts: Set<ServiceID> { get }
    var runtime: ServiceRuntime { get }
    var usesSharedAdminLogin: Bool { get }
    var resources: ServiceResources { get }
    var requiresPublicDomain: Bool { get }
    /// Only installable on a machine inside the house
    var requiresHomeMachine: Bool { get }

    /// docker-compose.yml (+ optional .env) to install; nil for systemd services
    func composeFile(_ context: ServiceContext) -> ComposeFile?
    func setupSteps(_ context: ServiceContext) -> [String]
    func firewallPorts(_ context: ServiceContext) -> [FirewallPort]
    /// HTTP endpoint to publish through the shared Caddy ingress
    func webIngress(_ context: ServiceContext) -> WebIngress?
    /// Additional DNS A-records (custom hostnames) pointing at the entry IP
    func dnsHostnames(_ context: ServiceContext) -> [String]
    func serviceRecords(_ context: ServiceContext) -> [ServiceRecord]
    func reportSteps(_ context: ServiceContext) -> [String]

    func actions(_ context: ServiceContext) -> ServiceActions
    func updateSpec(_ context: ServiceContext) -> UpdateSpec
    func extraSudoers(_ context: ServiceContext) -> [PrivilegedCommand]
    /// How this service is removed
    func uninstallSpec(_ context: ServiceContext) -> UninstallSpec
}

extension ManagedService {
    public var displayCategory: ServiceCategory { category }

    /// Nothing but addresses, for all but one service
    public func serviceRecords(_ context: ServiceContext) -> [ServiceRecord] { [] }

    public var usesSharedAdminLogin: Bool { false }

    public var conflicts: Set<ServiceID> {
        guard category.selection == .exclusive else { return [] }
        return Set(ServiceRegistry.all
            .filter { $0.category == category && $0.id != id }
            .map(\.id))
    }

    public var resources: ServiceResources { ServiceResources(memoryMB: 128, diskGB: 1) }

    public var requiresPublicDomain: Bool { false }

    public var requiresHomeMachine: Bool { false }

    public func sudoersLines(_ context: ServiceContext) -> [String] {
        let actions = actions(context)
        var commands: [PrivilegedCommand] = []
        commands.append(contentsOf: actions.statusProbe.privilegedCommands)
        if let restart = actions.restart { commands.append(restart.privileged) }
        if let start = actions.start { commands.append(start.privileged) }
        if let stop = actions.stop { commands.append(stop.privileged) }
        if let backup = actions.backup { commands.append(contentsOf: backup.privilegedCommands(context)) }
        if let restore = actions.restore { commands.append(restore.privileged) }
        if let logs = actions.logs { commands.append(logs.privileged) }
        commands.append(contentsOf: extraSudoers(context))
        var seen = Set<PrivilegedCommand>()
        return commands.compactMap { command in
            seen.insert(command).inserted ? command.sudoersLine(user: context.sshUser) : nil
        }
    }

    public func extraSudoers(_ context: ServiceContext) -> [PrivilegedCommand] { [] }

    public func reportSteps(_ context: ServiceContext) -> [String] { [] }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        var project: String?
        if case .docker(let composeProject) = runtime { project = composeProject }
        return UninstallSpec(composeProject: project,
                             configDirectory: composeFile(context)?.directory)
    }
}

/// A service's rough minimum resource footprint
public struct ServiceResources: Sendable, Hashable {
    /// RAM the running containers need, in mebibytes
    public let memoryMB: Int
    /// On-disk footprint — images plus a little data headroom, in gibibytes
    public let diskGB: Int

    public init(memoryMB: Int, diskGB: Int) {
        self.memoryMB = memoryMB
        self.diskGB = diskGB
    }
}

public struct ServerRequirements: Sendable, Hashable {
    /// Total RAM floor incl
    public let memoryMB: Int
    /// Total free-disk floor incl
    public let diskGB: Int
    public let installsDocker: Bool

    public init(memoryMB: Int, diskGB: Int, installsDocker: Bool) {
        self.memoryMB = memoryMB
        self.diskGB = diskGB
        self.installsDocker = installsDocker
    }

    /// RAM rounded up to whole gibibytes for display
    public var memoryGB: Int { Int((Double(memoryMB) / 1024.0).rounded(.up)) }
}

/// How the service runs on the server
public enum ServiceRuntime: Sendable, Hashable {
    case docker(composeProject: String)
}

/// A file the setup script writes for a docker service
public struct ComposeFile: Sendable, Hashable {
    public let directory: String        // e.g. "/opt/nextcloud"
    public let composeContents: String  // docker-compose.yml body
    /// Optional .env written next to the compose file
    public let envTemplate: String?

    public init(directory: String, composeContents: String, envTemplate: String? = nil) {
        self.directory = directory
        self.composeContents = composeContents
        self.envTemplate = envTemplate
    }
}

public struct ServiceRecord: Sendable, Hashable {
    /// The full record name, e.g
    public let name: String
    public let priority: Int
    public let weight: Int
    public let port: Int
    /// The host that answers, without a trailing dot
    public let target: String

    public init(name: String, priority: Int = 0, weight: Int = 5, port: Int, target: String) {
        self.name = name
        self.priority = priority
        self.weight = weight
        self.port = port
        self.target = target
    }
}

public struct FirewallPort: Sendable, Hashable {
    public enum Proto: String, Sendable { case tcp, udp }
    public let port: Int
    public let proto: Proto
    public let comment: String

    public init(_ port: Int, _ proto: Proto = .tcp, comment: String) {
        self.port = port
        self.proto = proto
        self.comment = comment
    }
}

/// HTTP endpoint published via the shared Caddy ingress
public struct WebIngress: Sendable, Hashable {
    public let hostname: String
    public let upstreamPort: Int
    public let adminGuard: Bool
    public let upstreamHTTPS: Bool
    public let publicPaths: [String]
    public let overwriteForwardedFor: Bool

    public init(hostname: String, upstreamPort: Int, adminGuard: Bool = true,
                upstreamHTTPS: Bool = false, publicPaths: [String] = [],
                overwriteForwardedFor: Bool = false) {
        self.hostname = hostname
        self.upstreamPort = upstreamPort
        self.adminGuard = adminGuard
        self.upstreamHTTPS = upstreamHTTPS
        self.publicPaths = publicPaths
        self.overwriteForwardedFor = overwriteForwardedFor
    }
}
