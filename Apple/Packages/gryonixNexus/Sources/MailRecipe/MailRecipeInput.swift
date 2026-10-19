import gryonixNexusCore
import ServiceCatalog

/// Input for the mail recipe
public struct MailRecipeInput: RecipeInput {
    public let domain: Domain
    /// Further domains the same server answers on
    public let additionalDomains: [Domain]
    public let hostname: String                  // e.g. mail.example.com
    /// Hostname the mail IP's PTR record should resolve to
    public let reverseDNSHostname: String?
    public let topology: Topology
    /// Public-internet (default) or local-network-only
    public let scope: DeploymentScope
    public let servers: [ServerNode]
    public let security: any SecurityPolicy
    public let dashboardAccess: DashboardAccessInput?
    /// Self-hosted services to install
    public let services: Set<ServiceID>
    public let serviceSettings: ServiceSettings
    public let language: AppLanguage

    public init(
        domain: Domain,
        additionalDomains: [Domain] = [],
        hostname: String,
        reverseDNSHostname: String? = nil,
        topology: Topology,
        scope: DeploymentScope = .publicInternet,
        servers: [ServerNode],
        security: any SecurityPolicy = DefaultSecurityPolicy(),
        dashboardAccess: DashboardAccessInput? = nil,
        services: Set<ServiceID> = [.mailcow],
        serviceSettings: ServiceSettings = ServiceSettings(),
        language: AppLanguage = .en
    ) {
        self.domain = domain
        self.additionalDomains = additionalDomains
        self.hostname = hostname
        self.reverseDNSHostname = reverseDNSHostname
        self.topology = topology
        self.scope = scope
        self.servers = servers
        self.security = security
        self.dashboardAccess = dashboardAccess
        self.services = services
        self.serviceSettings = serviceSettings
        self.language = language
    }
}
