import Foundation
import gryonixNexusCore
import MailRecipe
import ServerControl
import ServiceCatalog

enum ConfigurationExport {
    struct DNSZone: Identifiable {
        let domain: String
        let records: [DNSRecord]
        let copyText: String
        let zoneFile: Artifact?
        let csvFile: Artifact?
        var id: String { domain }
    }

    struct PortsBundle {
        let requirements: [OpenPortRequirement]
        let copyText: String
        let txtFile: Artifact
        let csvFile: Artifact
    }

    static func build(for deployment: Deployment) -> (dns: [DNSZone], ports: PortsBundle?) {
        guard let input = makeInput(for: deployment) else { return ([], nil) }
        return (dnsZones(for: input), ports(for: input))
    }

    // MARK: - Input

    private static func makeInput(for deployment: Deployment) -> MailRecipeInput? {
        var draft = ConfiguratorDraft(
            reinstalling: deployment,
            saved: ConfiguratorStore.shared.configForReinstall(deploymentID: deployment.id))
        draft.selectServices(deployment.services)
        return try? draft.makeMailRecipeInput()
    }

    // MARK: - DNS

    private static func dnsZones(for input: MailRecipeInput) -> [DNSZone] {
        let context = MailContext(input: input, renderer: StringTemplateRenderer())
        let generator = DNSRecordGenerator()
        let artifacts = (try? generator.generate(in: context)) ?? []
        let all = generator.records(in: context)
        let zones = context.mailDomainNames
        return zones.compactMap { zoneName in
            let owned = all.filter { DNSRecordGenerator.zone(of: $0, among: zones) == zoneName }
            guard !owned.isEmpty else { return nil }
            return DNSZone(
                domain: zoneName,
                records: owned,
                copyText: ConfigurationExportFormat.recordsText(owned, in: zoneName),
                zoneFile: artifacts.first { $0.fileName == DNSRecordGenerator.zoneFileName(domain: zoneName) },
                csvFile: artifacts.first { $0.fileName == DNSRecordGenerator.csvFileName(domain: zoneName) }
            )
        }
    }

    private static func ports(for input: MailRecipeInput) -> PortsBundle? {
        let requirements = OpenPortsSummary.entryHostPorts(for: input)
        guard !requirements.isEmpty else { return nil }
        return PortsBundle(
            requirements: requirements,
            copyText: ConfigurationExportFormat.portsText(requirements),
            txtFile: ConfigurationExportFormat.portsTextArtifact(
                requirements, summary: UIL10n.string("Ports to open as a text list")),
            csvFile: ConfigurationExportFormat.portsCSVArtifact(
                requirements, summary: UIL10n.string("Ports to open as CSV"))
        )
    }
}

extension ConfiguratorDraft {
    func makeMailRecipeInput() throws -> MailRecipeInput {
        func makeDomain(_ raw: String) throws -> Domain {
            localOnly ? try Domain(localOnly: raw) : try Domain(raw)
        }
        func makeAddress(_ raw: String) throws -> NetworkAddress {
            localOnly ? try NetworkAddress(localOnly: raw) : try NetworkAddress(parsing: raw)
        }
        let domainModel = try makeDomain(domain)
        let servers: [ServerNode]
        switch topology {
        case .singleHost:
            servers = [ServerNode(role: .singleHost,
                                  publicAddress: try makeAddress(publicIP),
                                  distribution: entryDistribution)]
        case .vpsRelayWithHomeBackend:
            servers = [
                ServerNode(role: .vpsRelay,
                           publicAddress: try NetworkAddress(parsing: publicIP),
                           vpnAddress: try NetworkAddress(parsing: vpsVPNIP),
                           distribution: entryDistribution),
                ServerNode(role: .homeBackend,
                           vpnAddress: try NetworkAddress(parsing: homeVPNIP),
                           distribution: homeDistributionID),
            ]
        }
        let trimmedPTR = reverseDNSHostname.trimmingCharacters(in: .whitespaces).lowercased()
        return MailRecipeInput(
            domain: domainModel,
            additionalDomains: try additionalDomains
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
                .map { try makeDomain($0) },
            hostname: "mail.\(domainModel.name)",
            reverseDNSHostname: trimmedPTR.isEmpty ? nil : trimmedPTR,
            topology: topology,
            scope: resolvedScope,
            servers: servers,
            services: services,
            serviceSettings: serviceSettings,
            language: ContentLanguageSetting.current
        )
    }

    private var resolvedScope: DeploymentScope {
        scope ?? (localOnly ? .localOnly : .publicInternet)
    }

    private var services: Set<ServiceID> {
        var services = extraServices
        if mailEnabled { services.insert(ServiceID(rawValue: mailEngineID)) }
        if vpnEnabled { services.formUnion(vpnProtocols) }
        // Same expansion as generation and the configurator — see `ServiceRegistry.expanded`.
        return ServiceRegistry.expanded(services, scope: resolvedScope,
                                        modelBackend: serviceSettings.modelBackend)
    }

    /// The service settings this configuration describes
    var serviceSettings: ServiceSettings {
        let defaults = ServiceSettings()
        func clean(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespaces).lowercased()
        }
        func port(_ text: String, _ fallback: Int) -> Int {
            Int(text.trimmingCharacters(in: .whitespaces)) ?? fallback
        }
        var settings = ServiceSettings(
            vaultwardenAllowSignups: vaultwardenAllowSignups,
            piholeServesNetwork: piholeServesNetwork ?? false,
            autheliaProtectedServices: autheliaProtectedServices
                ?? AutheliaService.defaultProtected,
            forgejoSSHPort: port(forgejoSSHPort, defaults.forgejoSSHPort),
            gitlabSSHPort: port(gitlabSSHPort, defaults.gitlabSSHPort),
            vpnHostname: clean(vpnHostname),
            vpnClientAccess: vpnClientAccess.flatMap(VPNClientAccess.init(rawValue:)) ?? .both,
            wireguardVPNPort: port(wireguardVPNPort, defaults.wireguardVPNPort),
            amneziaWGPort: port(amneziaWGPort, defaults.amneziaWGPort),
            shadowsocksPort: port(shadowsocksPort, defaults.shadowsocksPort),
            xrayRealityPort: port(xrayRealityPort, defaults.xrayRealityPort),
            xrayRealitySNI: {
                let trimmed = clean(xrayRealitySNI)
                return trimmed.isEmpty ? defaults.xrayRealitySNI : trimmed
            }(),
            openVPNPort: port(openVPNPort, defaults.openVPNPort),
            adminUsername: {
                let trimmed = adminUsername.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? defaults.adminUsername : trimmed
            }()
        )
        settings.minecraftJavaAcceptsEULA = minecraftJavaAcceptsEULA ?? false
        settings.minecraftJavaVersion = (minecraftJavaVersion ?? "").trimmingCharacters(in: .whitespaces)
        let flavour = (minecraftJavaFlavour ?? "").trimmingCharacters(in: .whitespaces)
        settings.minecraftJavaFlavour = flavour.isEmpty ? defaults.minecraftJavaFlavour : flavour
        settings.minecraftJavaMemoryMB = port(minecraftJavaMemoryMB ?? "", defaults.minecraftJavaMemoryMB)
        settings.minecraftJavaPort = port(minecraftJavaPort ?? "", defaults.minecraftJavaPort)
        settings.minecraftJavaWhitelist = (minecraftJavaWhitelist ?? "").trimmingCharacters(in: .whitespaces)
        settings.minecraftJavaOperators = (minecraftJavaOperators ?? "").trimmingCharacters(in: .whitespaces)
        settings.minecraftJavaMods = (minecraftJavaMods ?? "").trimmingCharacters(in: .whitespaces)
        settings.minecraftBedrockAcceptsEULA = minecraftBedrockAcceptsEULA ?? false
        settings.machineAtHome = machineAtHome ?? false
        settings.homeAssistantUSBDevice = (homeAssistantUSBDevice ?? "")
            .trimmingCharacters(in: .whitespaces)
        settings.minecraftBedrockVersion = (minecraftBedrockVersion ?? "").trimmingCharacters(in: .whitespaces)
        settings.minecraftBedrockPort = port(minecraftBedrockPort ?? "", defaults.minecraftBedrockPort)
        settings.openWebUIAllowSignups = openWebUIAllowSignups ?? defaults.openWebUIAllowSignups
        settings.ollamaUsesGPU = ollamaUsesGPU ?? defaults.ollamaUsesGPU
        settings.ollamaInstallsGPUDriver = ollamaInstallsGPUDriver ?? defaults.ollamaInstallsGPUDriver
        settings.modelBackend = modelBackend.flatMap(ModelBackend.init(rawValue:)) ?? defaults.modelBackend
        settings.crowdsecEnabled = crowdsecEnabled ?? defaults.crowdsecEnabled
        settings.applyHostnames(resolvedHostnames)
        return settings
    }
}
