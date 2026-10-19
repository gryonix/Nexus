package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.FirewallPort
import com.skaymer.gryonixnexus.catalog.HomePlacement
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.core.Domain
import com.skaymer.gryonixnexus.core.NetworkAddress
import com.skaymer.gryonixnexus.core.ServerRole
import com.skaymer.gryonixnexus.core.ValidationError
import com.skaymer.gryonixnexus.core.WireGuardDefaults

/** Validation of mail input: hostname format + topology consistency */
class MailInputValidator {
    fun validate(input: MailRecipeInput) {
        val context = ServiceContext(domain = input.domain.name, sshUser = "",
                                     settings = input.serviceSettings,
                                     installedServices = input.services)
        checkHostnames(input)
        checkDomains(input)
        checkServices(input)
        checkMailHostname(input)
        checkServiceHostnames(input, context)
        checkUDPPorts(input, context)
        checkTCPPorts(input, context)
        checkDashboardAccess(input)
        checkEULAs(input)
        checkTopology(input)
    }

    private fun checkHostnames(input: MailRecipeInput) {
        val isLocalOnly = input.scope == DeploymentScope.LOCAL_ONLY
        if (!isLocalOnly && !Domain.isValid(input.hostname)) {
            throw ValidationError.InvalidHostname(input.hostname)
        }
        val ptr = input.reverseDNSHostname?.trim().orEmpty()
        if (ptr.isNotEmpty() && !isLocalOnly && !Domain.isValid(ptr)) {
            throw ValidationError.InvalidHostname(ptr)
        }
    }

    private fun checkDomains(input: MailRecipeInput) {
        val language = input.language
        val seenDomains = mutableSetOf(input.domain.name)
        for (extra in input.additionalDomains) {
            if (!seenDomains.add(extra.name)) {
                throw ValidationError.InconsistentTopology(
                    L10nGeneration.errDuplicateDomain(language, extra.name))
            }
        }
        if (input.additionalDomains.size > MAX_ADDITIONAL_DOMAINS) {
            throw ValidationError.InconsistentTopology(
                L10nGeneration.errTooManyDomains(language, MAX_ADDITIONAL_DOMAINS))
        }
    }

    private fun checkServices(input: MailRecipeInput) {
        val language = input.language
        val conflicts = ServiceRegistry.conflicts(input.services)
        if (conflicts.isNotEmpty()) {
            val names = conflicts.joinToString(", ") { "${it.first.rawValue} + ${it.second.rawValue}" }
            throw ValidationError.InconsistentTopology(
                L10nGeneration.errConflictingServices(language, names))
        }
        if (input.scope == DeploymentScope.LOCAL_ONLY) checkLocalOnlyServices(input)
        checkHomeOnlyServices(input)
        checkHomeAssistantStick(input)
        checkSmartHomeAddOns(input)
        checkZigbeeStick(input)
        if (input.scope == DeploymentScope.CLOUDFLARE_TUNNEL) {
            val offender = ServiceRegistry.services(input.services).firstOrNull {
                it.requiresPublicDomain || it.id in ServiceID.VPN_PROTOCOLS ||
                    it.id == ServiceID.VPN_PANEL
            }
            if (offender != null) {
                throw ValidationError.InconsistentTopology(
                    L10nGeneration.errTunnelCarriesOnlyWeb(language, offender.displayName))
            }
        }
    }

    private fun checkHomeOnlyServices(input: MailRecipeInput) {
        val atHome = HomePlacement.isAtHome(input.topology, input.scope,
            input.serviceSettings.machineAtHome)
        if (atHome) return
        val offender = ServiceRegistry.services(input.services).firstOrNull { it.requiresHomeMachine }
            ?: return
        throw ValidationError.InconsistentTopology(
            L10nGeneration.errServiceNeedsHomeMachine(input.language, offender.displayName))
    }

    /** An add-on alone has nobody to talk to */
    private fun checkSmartHomeAddOns(input: MailRecipeInput) {
        val addOn = input.services.firstOrNull { it in ServiceID.SMART_HOME_ADD_ONS } ?: return
        if (ServiceID.HOME_ASSISTANT in input.services) return
        val service = ServiceRegistry.service(addOn) ?: return
        throw ValidationError.InconsistentTopology(
            L10nGeneration.errAddOnNeedsTheHub(input.language, service.displayName))
    }

    /** Zigbee talks to a radio: a stick on the machine */
    private fun checkZigbeeStick(input: MailRecipeInput) {
        if (ServiceID.ZIGBEE2MQTT !in input.services) return
        if (input.serviceSettings.homeAssistantUSBDevice.trim().isNotEmpty()) return
        throw ValidationError.InconsistentTopology(
            L10nGeneration.errZigbeeNeedsAStick(input.language))
    }

    /** A wrong device path never starts the container */
    private fun checkHomeAssistantStick(input: MailRecipeInput) {
        val device = input.serviceSettings.homeAssistantUSBDevice.trim()
        if (device.isEmpty() || ServiceID.HOME_ASSISTANT !in input.services) return
        val looksLikeADevice = device.startsWith("/dev/") &&
            !device.contains("..") &&
            !device.contains(" ") &&
            device.length > "/dev/".length
        if (looksLikeADevice) return
        throw ValidationError.InconsistentTopology(
            L10nGeneration.errStickIsNotADevicePath(input.language, device))
    }

    private fun checkLocalOnlyServices(input: MailRecipeInput) {
        val language = input.language
        val offender = ServiceRegistry.services(input.services)
            .firstOrNull { it.requiresPublicDomain }
        if (offender != null) {
            throw ValidationError.InconsistentTopology(
                L10nGeneration.errLocalOnlyRequiresPublicDomain(language, offender.displayName))
        }
        val vpnOffender = input.services
            .intersect(ServiceID.VPN_PROTOCOLS + ServiceID.VPN_PANEL)
            .firstOrNull()
        val vpnService = vpnOffender?.let { ServiceRegistry.service(it) }
        if (vpnService != null) {
            throw ValidationError.InconsistentTopology(
                L10nGeneration.errLocalOnlyRequiresPublicIP(language, vpnService.displayName))
        }
    }

    private fun checkMailHostname(input: MailRecipeInput) {
        val language = input.language
        val engine = ServiceRegistry.mailEngines.firstOrNull { it.id in input.services }
        if (engine != null) {
            val required = engine.requiredHostname(input.domain.name)
            if (required != null && input.hostname != required) {
                throw ValidationError.InconsistentTopology(
                    L10nGeneration.errRequiredMailHostname(language, engine.displayName, required))
            }
        }
    }

    private fun checkServiceHostnames(input: MailRecipeInput, context: ServiceContext) {
        val language = input.language
        val isLocalOnly = input.scope == DeploymentScope.LOCAL_ONLY
        val seenSiteNames = mutableSetOf<String>()
        for (service in ServiceRegistry.services(input.services)) {
            for (hostname in service.dnsHostnames(context)) {
                if (!isValidServiceHostname(hostname, input.domain.name, isLocalOnly)) {
                    throw ValidationError.InvalidHostname(hostname)
                }
            }
            val ingress = service.webIngress(context) ?: continue
            if (!seenSiteNames.add(ingress.hostname.lowercase())) {
                throw ValidationError.InconsistentTopology(
                    L10nGeneration.errDuplicateServiceHostname(language, ingress.hostname))
            }
        }
    }

    private fun checkUDPPorts(input: MailRecipeInput, context: ServiceContext) {
        val language = input.language
        val seenUDPPorts = mutableSetOf<Int>()
        for (service in ServiceRegistry.services(input.services)) {
            for (udp in service.firewallPorts(context)) {
                if (udp.proto != FirewallPort.Proto.UDP) continue
                if (udp.port !in 1..65535) {
                    throw ValidationError.InconsistentTopology(
                        L10nGeneration.errInvalidVPNPort(language, udp.port))
                }
                if (input.topology == Topology.VPS_RELAY_WITH_HOME_BACKEND &&
                    udp.port == WireGuardDefaults.LISTEN_PORT) {
                    throw ValidationError.InconsistentTopology(
                        L10nGeneration.errVPNPortCollidesWithTunnel(language, udp.port))
                }
                if (!seenUDPPorts.add(udp.port)) {
                    throw ValidationError.InconsistentTopology(
                        L10nGeneration.errVPNPortCollidesWithService(language, udp.port))
                }
            }
        }
    }

    private fun checkTCPPorts(input: MailRecipeInput, context: ServiceContext) {
        val language = input.language
        val webPresent = ServiceRegistry.services(input.services)
            .any { it.webIngress(context) != null } ||
            input.services.any { it in ServiceID.VPN_PROTOCOLS }
        val reservedTCP = mutableMapOf(80 to "HTTP/ACME")
        if (webPresent) reservedTCP[443] = "Caddy"
        reservedTCP[input.security.ssh.port] = "SSH"
        for (service in ServiceRegistry.services(input.services)) {
            for (tcp in service.firewallPorts(context)) {
                if (tcp.proto != FirewallPort.Proto.TCP) continue
                val owner = reservedTCP[tcp.port]
                if (owner != null) {
                    throw ValidationError.InconsistentTopology(
                        L10nGeneration.errServicePortInUse(language, tcp.port, owner))
                }
                reservedTCP[tcp.port] = service.displayName
            }
        }
    }

    private fun checkDashboardAccess(input: MailRecipeInput) {
        val language = input.language
        val access = input.dashboardAccess ?: return
        if (!access.hasValidUser) {
            throw ValidationError.InconsistentTopology(
                L10nGeneration.errInvalidDashboardUser(language, access.sshUser))
        }
        if (!access.hasValidKey) {
            throw ValidationError.InconsistentTopology(
                L10nGeneration.errInvalidDashboardKey(language))
        }
        if (!access.hasValidContainerName) {
            throw ValidationError.InconsistentTopology(
                L10nGeneration.errInvalidContainerName(language, access.vaultwardenContainer))
        }
        if (!access.hasValidPaths) {
            throw ValidationError.InconsistentTopology(L10nGeneration.errInvalidPaths(language))
        }
    }

    private fun checkEULAs(input: MailRecipeInput) {
        val language = input.language
        val settings = input.serviceSettings
        if (ServiceID.MINECRAFT_JAVA in input.services && !settings.minecraftJavaAcceptsEULA) {
            throw ValidationError.InconsistentTopology(L10nGeneration.errMinecraftEULA(language))
        }
        if (ServiceID.MINECRAFT_BEDROCK in input.services && !settings.minecraftBedrockAcceptsEULA) {
            throw ValidationError.InconsistentTopology(L10nGeneration.errMinecraftEULA(language))
        }
    }

    private fun checkTopology(input: MailRecipeInput) {
        val language = input.language
        when (input.topology) {
            Topology.SINGLE_HOST -> {
                val host = input.servers.singleOrNull()
                if (host == null || host.role != ServerRole.SINGLE_HOST) {
                    throw ValidationError.InconsistentTopology(
                        L10nGeneration.errSingleHostTopology(language))
                }
                if (host.publicAddress == null) {
                    throw ValidationError.MissingPublicIP(ServerRole.SINGLE_HOST)
                }
            }

            Topology.VPS_RELAY_WITH_HOME_BACKEND -> checkSplitTopology(input)
        }
    }

    private fun checkSplitTopology(input: MailRecipeInput) {
        val language = input.language
        val vps = input.servers.firstOrNull { it.role == ServerRole.VPS_RELAY }
        val home = input.servers.firstOrNull { it.role == ServerRole.HOME_BACKEND }
        if (input.servers.size != 2 || vps == null || home == null) {
            throw ValidationError.InconsistentTopology(
                L10nGeneration.errSplitTopology(language))
        }
        if (vps.publicAddress == null) {
            throw ValidationError.MissingPublicIP(ServerRole.VPS_RELAY)
        }
        val vpsVPN = vps.vpnAddress
            ?: throw ValidationError.MissingVPNAddress(ServerRole.VPS_RELAY)
        val homeVPN = home.vpnAddress
            ?: throw ValidationError.MissingVPNAddress(ServerRole.HOME_BACKEND)
        if (vpsVPN !is NetworkAddress.IPv4 || homeVPN !is NetworkAddress.IPv4) {
            throw ValidationError.InconsistentTopology(L10nGeneration.errWGNotIPv4(language))
        }
        if (vpsVPN.value == homeVPN.value) {
            throw ValidationError.InconsistentTopology(
                L10nGeneration.errWGSameAddress(language))
        }
        if (vpsVPN.value.split(".").dropLast(1) != homeVPN.value.split(".").dropLast(1)) {
            throw ValidationError.InconsistentTopology(L10nGeneration.errWGSubnet(language))
        }
    }

    companion object {
        const val MAX_ADDITIONAL_DOMAINS = 9

        private fun isValidServiceHostname(hostname: String, domain: String,
                                           isLocalOnly: Boolean): Boolean {
            if (Domain.isValid(hostname, allowLocalAddress = isLocalOnly)) return true
            if (!isLocalOnly) return false
            return hostname == domain || hostname.endsWith(".$domain")
        }
    }
}
