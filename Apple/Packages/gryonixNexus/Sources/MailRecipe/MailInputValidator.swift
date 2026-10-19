import gryonixNexusCore
import ServiceCatalog

/// Validation of mail input: hostname format + topology consistency
public struct MailInputValidator: InputValidator {
    public typealias Input = MailRecipeInput

    public static let maxAdditionalDomains = 9

    public init() {}

    public func validate(_ input: MailRecipeInput) throws {
        let context = ServiceContext(domain: input.domain.name, sshUser: "",
                                     settings: input.serviceSettings,
                                     installedServices: input.services)
        try checkHostnames(input)
        try checkDomains(input)
        try checkServices(input)
        try checkMailHostname(input)
        try checkServiceHostnames(input, context: context)
        try checkUDPPorts(input, context: context)
        try checkTCPPorts(input, context: context)
        try checkDashboardAccess(input)
        try checkEULAs(input)
        try checkTopology(input)
    }

    private func checkHostnames(_ input: MailRecipeInput) throws {
        let isLocalOnly = input.scope == .localOnly
        guard isLocalOnly || Domain.isValid(input.hostname) else {
            throw ValidationError.invalidHostname(input.hostname)
        }
        if let ptr = input.reverseDNSHostname?.trimmingCharacters(in: .whitespaces),
           !ptr.isEmpty, !isLocalOnly, !Domain.isValid(ptr) {
            throw ValidationError.invalidHostname(ptr)
        }
    }

    private func checkDomains(_ input: MailRecipeInput) throws {
        let language = input.language
        var seenDomains = Set([input.domain.name])
        for extra in input.additionalDomains {
            guard seenDomains.insert(extra.name).inserted else {
                throw ValidationError.inconsistentTopology(
                    L10nGeneration.errDuplicateDomain(language, domain: extra.name))
            }
        }
        guard input.additionalDomains.count <= Self.maxAdditionalDomains else {
            throw ValidationError.inconsistentTopology(
                L10nGeneration.errTooManyDomains(language, limit: Self.maxAdditionalDomains))
        }
    }

    private func checkServices(_ input: MailRecipeInput) throws {
        let language = input.language
        let conflicts = ServiceRegistry.conflicts(in: input.services)
        guard conflicts.isEmpty else {
            let names = conflicts.map { "\($0.0.rawValue) + \($0.1.rawValue)" }.joined(separator: ", ")
            throw ValidationError.inconsistentTopology(L10nGeneration.errConflictingServices(language, names: names))
        }
        if input.scope == .localOnly { try checkLocalOnlyServices(input) }
        try checkHomeOnlyServices(input)
        try checkHomeAssistantStick(input)
        try checkSmartHomeAddOns(input)
        try checkZigbeeStick(input)
        if input.scope == .cloudflareTunnel {
            let offenders = ServiceRegistry.services(input.services)
                .filter { $0.requiresPublicDomain || ServiceID.vpnProtocols.contains($0.id) || $0.id == .vpnPanel }
            if let offender = offenders.first {
                throw ValidationError.inconsistentTopology(
                    L10nGeneration.errTunnelCarriesOnlyWeb(language, service: offender.displayName))
            }
        }
    }

    private func checkHomeOnlyServices(_ input: MailRecipeInput) throws {
        let atHome = HomePlacement.isAtHome(topology: input.topology, scope: input.scope,
                                            machineAtHome: input.serviceSettings.machineAtHome)
        guard !atHome,
              let offender = ServiceRegistry.services(input.services).first(where: \.requiresHomeMachine)
        else { return }
        throw ValidationError.inconsistentTopology(
            L10nGeneration.errServiceNeedsHomeMachine(input.language, service: offender.displayName))
    }

    /// An add-on alone has nobody to talk to
    private func checkSmartHomeAddOns(_ input: MailRecipeInput) throws {
        let addOns = input.services.intersection(ServiceID.smartHomeAddOns)
        guard let addOn = addOns.first, !input.services.contains(.homeAssistant),
              let service = ServiceRegistry.service(addOn)
        else { return }
        throw ValidationError.inconsistentTopology(
            L10nGeneration.errAddOnNeedsTheHub(input.language, service: service.displayName))
    }

    /// Zigbee talks to a radio: a stick on the machine
    private func checkZigbeeStick(_ input: MailRecipeInput) throws {
        guard input.services.contains(.zigbee2MQTT),
              input.serviceSettings.homeAssistantUSBDevice
                  .trimmingCharacters(in: .whitespaces).isEmpty
        else { return }
        throw ValidationError.inconsistentTopology(
            L10nGeneration.errZigbeeNeedsAStick(input.language))
    }

    /// A wrong device path never starts the container
    private func checkHomeAssistantStick(_ input: MailRecipeInput) throws {
        let device = input.serviceSettings.homeAssistantUSBDevice
            .trimmingCharacters(in: .whitespaces)
        guard !device.isEmpty, input.services.contains(.homeAssistant) else { return }
        let looksLikeADevice = device.hasPrefix("/dev/")
            && !device.contains("..")
            && !device.contains(" ")
            && device.count > "/dev/".count
        guard !looksLikeADevice else { return }
        throw ValidationError.inconsistentTopology(
            L10nGeneration.errStickIsNotADevicePath(input.language, value: device))
    }

    private func checkLocalOnlyServices(_ input: MailRecipeInput) throws {
        let language = input.language
        let offenders = ServiceRegistry.services(input.services).filter(\.requiresPublicDomain)
        if let offender = offenders.first {
            throw ValidationError.inconsistentTopology(
                L10nGeneration.errLocalOnlyRequiresPublicDomain(language, service: offender.displayName))
        }
        if let vpnOffender = input.services.intersection(ServiceID.vpnProtocols.union([.vpnPanel])).first,
           let service = ServiceRegistry.service(vpnOffender) {
            throw ValidationError.inconsistentTopology(
                L10nGeneration.errLocalOnlyRequiresPublicIP(language, service: service.displayName))
        }
    }

    private func checkMailHostname(_ input: MailRecipeInput) throws {
        if let engine = ServiceRegistry.mailEngines.first(where: { input.services.contains($0.id) }),
           let required = engine.requiredHostname(forDomain: input.domain.name),
           input.hostname != required {
            throw ValidationError.inconsistentTopology(
                L10nGeneration.errRequiredMailHostname(input.language, engine: engine.displayName,
                                                       hostname: required)
            )
        }
    }

    private func checkServiceHostnames(_ input: MailRecipeInput, context: ServiceContext) throws {
        let isLocalOnly = input.scope == .localOnly
        var seenSiteNames: Set<String> = []
        for service in ServiceRegistry.services(input.services) {
            for hostname in service.dnsHostnames(context)
                where !Self.isValidServiceHostname(hostname, domain: input.domain.name,
                                                   isLocalOnly: isLocalOnly) {
                throw ValidationError.invalidHostname(hostname)
            }
            guard let ingress = service.webIngress(context) else { continue }
            guard seenSiteNames.insert(ingress.hostname.lowercased()).inserted else {
                throw ValidationError.inconsistentTopology(
                    L10nGeneration.errDuplicateServiceHostname(input.language, hostname: ingress.hostname))
            }
        }
    }

    private func checkUDPPorts(_ input: MailRecipeInput, context: ServiceContext) throws {
        let language = input.language
        var seenUDPPorts: Set<Int> = []
        for service in ServiceRegistry.services(input.services) {
            for udp in service.firewallPorts(context) where udp.proto == .udp {
                guard (1...65535).contains(udp.port) else {
                    throw ValidationError.inconsistentTopology(
                        L10nGeneration.errInvalidVPNPort(language, port: udp.port))
                }
                if input.topology == .vpsRelayWithHomeBackend, udp.port == WireGuardDefaults.listenPort {
                    throw ValidationError.inconsistentTopology(
                        L10nGeneration.errVPNPortCollidesWithTunnel(language, port: udp.port)
                    )
                }
                guard seenUDPPorts.insert(udp.port).inserted else {
                    throw ValidationError.inconsistentTopology(
                        L10nGeneration.errVPNPortCollidesWithService(language, port: udp.port)
                    )
                }
            }
        }
    }

    private func checkTCPPorts(_ input: MailRecipeInput, context: ServiceContext) throws {
        let webPresent = ServiceRegistry.services(input.services)
            .contains { $0.webIngress(context) != nil }
            || !input.services.isDisjoint(with: ServiceID.vpnProtocols)
        var reservedTCP: [Int: String] = [80: "HTTP/ACME"]
        if webPresent { reservedTCP[443] = "Caddy" }
        reservedTCP[input.security.ssh.port] = "SSH"
        for service in ServiceRegistry.services(input.services) {
            for tcp in service.firewallPorts(context) where tcp.proto == .tcp {
                if let owner = reservedTCP[tcp.port] {
                    throw ValidationError.inconsistentTopology(
                        L10nGeneration.errServicePortInUse(input.language, port: tcp.port, owner: owner)
                    )
                }
                reservedTCP[tcp.port] = service.displayName
            }
        }
    }

    private func checkDashboardAccess(_ input: MailRecipeInput) throws {
        guard let access = input.dashboardAccess else { return }
        let language = input.language
        guard access.hasValidUser else {
            throw ValidationError.inconsistentTopology(
                L10nGeneration.errInvalidDashboardUser(language, user: access.sshUser)
            )
        }
        guard access.hasValidKey else {
            throw ValidationError.inconsistentTopology(L10nGeneration.errInvalidDashboardKey(language))
        }
        guard access.hasValidContainerName else {
            throw ValidationError.inconsistentTopology(
                L10nGeneration.errInvalidContainerName(language, name: access.vaultwardenContainer)
            )
        }
        guard access.hasValidPaths else {
            throw ValidationError.inconsistentTopology(L10nGeneration.errInvalidPaths(language))
        }
    }

    private func checkEULAs(_ input: MailRecipeInput) throws {
        let settings = input.serviceSettings
        if input.services.contains(.minecraftJava), !settings.minecraftJavaAcceptsEULA {
            throw ValidationError.inconsistentTopology(L10nGeneration.errMinecraftEULA(input.language))
        }
        if input.services.contains(.minecraftBedrock), !settings.minecraftBedrockAcceptsEULA {
            throw ValidationError.inconsistentTopology(L10nGeneration.errMinecraftEULA(input.language))
        }
    }

    private func checkTopology(_ input: MailRecipeInput) throws {
        switch input.topology {
        case .singleHost:
            guard input.servers.count == 1, let host = input.servers.first, host.role == .singleHost else {
                throw ValidationError.inconsistentTopology(L10nGeneration.errSingleHostTopology(input.language))
            }
            guard host.publicAddress != nil else {
                throw ValidationError.missingPublicIP(role: .singleHost)
            }
        case .vpsRelayWithHomeBackend:
            try checkSplitTopology(input)
        }
    }

    private func checkSplitTopology(_ input: MailRecipeInput) throws {
        let language = input.language
        guard input.servers.count == 2,
              let vps = input.servers.first(where: { $0.role == .vpsRelay }),
              let home = input.servers.first(where: { $0.role == .homeBackend }) else {
            throw ValidationError.inconsistentTopology(L10nGeneration.errSplitTopology(language))
        }
        guard vps.publicAddress != nil else {
            throw ValidationError.missingPublicIP(role: .vpsRelay)
        }
        guard let vpsVPN = vps.vpnAddress else {
            throw ValidationError.missingVPNAddress(role: .vpsRelay)
        }
        guard let homeVPN = home.vpnAddress else {
            throw ValidationError.missingVPNAddress(role: .homeBackend)
        }
        guard case .ipv4(let vpsIP) = vpsVPN, case .ipv4(let homeIP) = homeVPN else {
            throw ValidationError.inconsistentTopology(L10nGeneration.errWGNotIPv4(language))
        }
        guard vpsIP != homeIP else {
            throw ValidationError.inconsistentTopology(L10nGeneration.errWGSameAddress(language))
        }
        guard vpsIP.split(separator: ".").dropLast() == homeIP.split(separator: ".").dropLast() else {
            throw ValidationError.inconsistentTopology(L10nGeneration.errWGSubnet(language))
        }
    }

    private static func isValidServiceHostname(_ hostname: String, domain: String, isLocalOnly: Bool) -> Bool {
        if Domain.isValid(hostname, allowLocalAddress: isLocalOnly) { return true }
        guard isLocalOnly else { return false }
        return hostname == domain || hostname.hasSuffix(".\(domain)")
    }
}
