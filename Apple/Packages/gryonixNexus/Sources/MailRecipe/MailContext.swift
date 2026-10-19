import gryonixNexusCore
import ServiceCatalog

/// Shared tunnel constants for scenario B
public struct MailContext: GenerationContext {
    public let input: MailRecipeInput
    public let renderer: any TemplateRenderer

    public init(input: MailRecipeInput, renderer: any TemplateRenderer) {
        self.input = input
        self.renderer = renderer
    }

    // MARK: Nodes and profiles

    public func server(_ role: ServerRole) -> ServerNode? {
        input.servers.first { $0.role == role }
    }

    public func distributionProfile(for role: ServerRole) -> any DistributionProfile {
        (server(role)?.distribution ?? .debian).makeProfile()
    }

    /// The node where mail lives
    public var mailHostRole: ServerRole {
        input.topology == .singleHost ? .singleHost : .homeBackend
    }

    public var entryRole: ServerRole {
        input.topology == .singleHost ? .singleHost : .vpsRelay
    }

    public var mailHost: ServerNode? { server(mailHostRole) }
    public var entryPoint: ServerNode? { server(entryRole) }

    // MARK: Convenience values

    public var domainName: String { input.domain.name }
    public var additionalDomainNames: [String] {
        var seen = Set([domainName])
        return input.additionalDomains.map(\.name).filter { seen.insert($0).inserted }
    }
    /// Every mail domain: the primary one plus the additional ones
    public var mailDomainNames: [String] { [domainName] + additionalDomainNames }

    /// The same web hostname mirrored onto every additional domain
    public func mirroredHostnames(of hostname: String) -> [String] {
        guard hostname.hasSuffix(".\(domainName)") else { return [] }
        let prefix = String(hostname.dropLast(domainName.count + 1))
        return additionalDomainNames.map { "\(prefix).\($0)" }
    }

    public var hostname: String { input.hostname }
    public var ptrHostname: String {
        let custom = input.reverseDNSHostname?.trimmingCharacters(in: .whitespaces) ?? ""
        return custom.isEmpty ? "relay.\(domainName)" : custom
    }
    public var security: any SecurityPolicy { input.security }
    /// Language of all user-visible generated content
    public var language: AppLanguage { input.language }
    /// Public-internet or LAN-only — see `DeploymentScope`
    public var scope: DeploymentScope { input.scope }
    /// LAN-only: no DNS-records artifact, Caddy self-signs instead of ACME
    public var isLocalOnly: Bool { scope == .localOnly }

    public var usesInternalTLS: Bool { scope.usesInternalTLS }

    /// The deployment publishes A records naming its own address
    public var publishesAddressRecords: Bool { scope.publishesAddressRecords }

    public var forwardedPorts: [Int] {
        ForwardedPorts.tcp(services: allSelectedServices, context: serviceContext)
    }

    /// UDP ports declared by the selected services (e.g
    public var forwardedUDPPorts: [Int] {
        ForwardedPorts.udp(services: allSelectedServices, context: serviceContext)
    }

    /// WireGuard subnet, derived from the VPS's VPN address (e.g
    public var wireGuardSubnet: String? {
        guard case .ipv4(let ip)? = server(.vpsRelay)?.vpnAddress else { return nil }
        return ip.split(separator: ".").dropLast().joined(separator: ".") + ".0/24"
    }

    /// Context that services use to describe themselves during generation
    public var serviceContext: ServiceContext {
        var settings = input.serviceSettings
        if settings.tailscaleLoginServer.isEmpty, input.services.contains(.headscale) {
            settings.tailscaleLoginServer = "http://127.0.0.1:\(HeadscaleService.webUIPort)"
        }
        return ServiceContext(domain: domainName, additionalDomains: additionalDomainNames,
                              sshUser: "", settings: settings, language: language,
                              installedServices: input.services, usesInternalTLS: usesInternalTLS)
    }

    public var mailEngine: (any MailEngineService)? {
        ServiceRegistry.mailEngines.first { input.services.contains($0.id) }
    }

    public var hasMail: Bool { mailEngine != nil }

    public var additionalServices: [any ManagedService] {
        var ids = ServiceRegistry.expanded(input.services, scope: scope,
                                           modelBackend: input.serviceSettings.modelBackend)
        if let mailEngine { ids.remove(mailEngine.id) }
        return ServiceRegistry.services(ids)
    }

    public var allSelectedServices: [any ManagedService] {
        var services = additionalServices
        if let mailEngine {
            services.insert(mailEngine, at: 0)
        }
        return services
    }

    public var needsDocker: Bool { !allSelectedServices.isEmpty }

    public var webServices: [any ManagedService] {
        allSelectedServices.filter { $0.webIngress(serviceContext) != nil }
    }

    public var needsCaddy: Bool { !webServices.isEmpty }
}
