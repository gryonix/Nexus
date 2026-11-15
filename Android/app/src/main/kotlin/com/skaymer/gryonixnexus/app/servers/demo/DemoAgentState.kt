package com.skaymer.gryonixnexus.app.servers.demo

import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.recipe.AgentBootstrapSections
import gryonixnexusd.v1.Device
import gryonixnexusd.v1.Job
import gryonixnexusd.v1.VaultEntry
import java.util.UUID

/** The agent version a demo machine reports */
object DemoAgentOffer {
    val installedVersion: String get() = AgentBootstrapSections.BUNDLED_VERSION

    val publishedVersion: String? get() = null
}

/** What the demo agent remembers between calls */
object DemoAgentState {
    class Ban(
        val id: String,
        val scope: String,
        val value: String,
        val reason: String,
        val country: String,
        val asName: String,
        val source: String,
        val expiresIn: String,
        val events: Int,
    )

    class Allowed(val value: String, val comment: String)

    class VPNDevice(val id: String, val name: String, val detail: String, var dns: List<String> = listOf("1.1.1.1"))

    class MeshMember(
        val id: String,
        val name: String,
        val address: String,
        val user: String,
        val online: Boolean,
        val lastSeenMillis: Long,
    )

    class Memory {
        var notify: gryonixnexusd.v1.NotifySettings? = null
        var passwordLoginOpen = false
        var keyOnlyUsers = mutableSetOf<String>()
        val lockedOutUsers = mutableSetOf("backup")
        val bans = mutableListOf<Ban>()
        val allowlist = mutableListOf<Allowed>()
        var autoRulesEnabled = false
        var autoRuleCountries = listOf<String>()
        var dynamicDNSEnabled = false
        var dynamicDNSNames = listOf<String>()
        var autoLogoutMonths = 0
        val devices = mutableListOf<Device>()
        val jobs = mutableListOf<Job>()
        val vault = mutableMapOf<String, VaultEntry>()
        val models = mutableListOf("llama3.2:3b", "qwen2.5:7b")
        val modFiles = mutableMapOf<String, MutableList<String>>()
        val removedImages = mutableSetOf<String>()
        val removedVolumes = mutableSetOf<String>()

        /** Per VPN protocol id */
        val vpnClients = mutableMapOf<String, MutableList<VPNDevice>>()
        val nextOctet = mutableMapOf<String, Int>()
        var vpnDefaultDNS = listOf("1.1.1.1")
        var vpnDNSPriority = listOf("local", "1.1.1.1")
        val meshUsers = mutableListOf("1" to "gryonixnexus", "2" to "devices")
        val meshNodes = mutableListOf<MeshMember>()
        var meshNames = listOf<Pair<String, String>>()
        val groupNames = mutableMapOf<String, String>()
        val removedGroups = mutableSetOf<String>()
        val stoppedGroups = mutableSetOf<String>()
        val removedNetworks = mutableSetOf<String>()
        var appModules = listOf("dockerAdvanced", "portForwarding")
        val serviceNames = mutableMapOf<String, String>()
        var mcpOn = false
        val localAliases = mutableListOf<String>()
        var homeOnlyPorts = listOf<gryonixnexusd.v1.HomeOnlyPort>()
        var agentAutoUpdate = true
        val deletedCopies = mutableSetOf<String>()
        val openAPI = mutableMapOf<String, List<String>>()
    }

    private val memories = mutableMapOf<String, Memory>()

    @Synchronized
    fun forgetEverything() = memories.clear()

    /** Reads or changes one machine's memory */
    @Synchronized
    fun <T> memory(machine: DemoAgentMachine, use: (Memory) -> T): T =
        use(memories.getOrPut(machine.id) { seeded(machine) })

    private fun seeded(machine: DemoAgentMachine): Memory = Memory().apply {
        devices += device("iPhone", 86_400L * 12)
        devices += device("MacBook Pro", 86_400L * 40)
        keyOnlyUsers = mutableSetOf(machine.deployment.dashboardConfig.sshUser)
        bans += seededBans
        allowlist += Allowed("203.0.113.9", "office")
        meshNodes += seededMesh(machine)
        vpnClients += seededVPN(machine)
        vault += seededVault(machine)
    }

    private fun device(label: String, agoSeconds: Long): Device = Device(
        id = UUID.randomUUID().toString(),
        label = label,
        public_key = "ssh-ed25519 DEMO+${label.replace(" ", "")}",
        scopes = listOf("read"),
        paired_at = System.currentTimeMillis() - agoSeconds * 1000,
        last_seen_at = System.currentTimeMillis() - 3_600_000,
    )

    private val seededBans = listOf(
        Ban("270036", "Ip", "193.233.199.37", "crowdsecurity/ssh-slow-bf", "RU", "44812 IPHOST", "crowdsec", "3h6m42s", 11),
        Ban("270041", "Range", "198.51.100.0/24", "gryonixnexus: added by hand", "", "", "cscli", "22h14m", 1),
    )

    private fun seededMesh(machine: DemoAgentMachine): List<MeshMember> {
        if (ServiceID.HEADSCALE !in machine.deployment.services) return emptyList()
        val now = System.currentTimeMillis()
        return listOf(
            MeshMember("1", "gryonix-com", "100.64.0.1", "gryonixnexus", true, now),
            MeshMember("2", "iphone", "100.64.0.2", "devices", true, now - 180_000),
            MeshMember("3", "macbook-air", "100.64.0.3", "devices", false, now - 7_200_000),
        )
    }

    /** The devices each protocol on this machine starts with */
    private fun seededVPN(machine: DemoAgentMachine): Map<String, MutableList<VPNDevice>> =
        machine.deployment.services.filter { it in ServiceID.VPN_PROTOCOLS }.mapNotNull { id ->
            val names = startingNames(machine.id, id)
            if (names.isEmpty()) null
            else id.rawValue to names.mapIndexed { index, name -> device(name, id, index + 2) }.toMutableList()
        }.toMap()

    private fun startingNames(deployment: String, id: ServiceID): List<String> {
        val pair = DemoDeployments.isDemoID(deployment) && deployment.endsWith("2")
        return when {
            !pair && id == ServiceID.WIREGUARD_VPN -> listOf("iPhone", "MacBook Air", "iPad")
            !pair && id == ServiceID.AMNEZIA_WG -> listOf("iPhone abroad", "Travel laptop")
            !pair && id == ServiceID.XRAY_REALITY -> listOf("Work phone")
            pair && id == ServiceID.WIREGUARD_VPN -> listOf("Phone", "Work laptop")
            pair && id == ServiceID.SHADOWSOCKS -> listOf("Tablet")
            pair && id == ServiceID.OPEN_VPN -> listOf("Old router", "Windows PC")
            pair && id == ServiceID.XRAY_REALITY -> listOf("Travel phone")
            else -> emptyList()
        }
    }

    fun device(name: String, id: ServiceID, octet: Int): VPNDevice = when (id) {
        ServiceID.AMNEZIA_WG -> VPNDevice("awg-$octet", name, "10.10.0.$octet")
        ServiceID.OPEN_VPN -> VPNDevice("ovpn-$octet", name, "certificate")
        ServiceID.SHADOWSOCKS -> VPNDevice("ss-$octet", name, "Shadowsocks")
        ServiceID.XRAY_REALITY -> VPNDevice("xray-$octet", name, "VLESS · Reality")
        else -> VPNDevice("wg-$octet", name, "10.9.0.$octet")
    }

    /** The passwords a demo installation would have written */
    private fun seededVault(machine: DemoAgentMachine): Map<String, VaultEntry> {
        val domain = machine.deployment.domain
        return machine.installed.take(4).associate { service ->
            val id = service.id.rawValue
            id to VaultEntry(
                id = id,
                title = service.displayName,
                website = "$id.$domain",
                login = "admin@$domain",
                password = "DEMO-NOT-A-PASSWORD",
                updated_at = System.currentTimeMillis(),
                updated_by = "the installation",
            )
        }
    }

    // Dispatch

    fun unary(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? =
        DemoAgentControl.answer(path, request, machine)
            ?: DemoAgentSecurity.answer(path, request, machine)
            ?: DemoAgentNotify.answer(path, request, machine)
            ?: DemoAgentMaintenance.answer(path, request, machine)
            ?: DemoAgentServices.answer(path, request, machine)
            ?: DemoAgentGaps.answer(path, request, machine)

    fun stream(path: String, request: ByteArray, machine: DemoAgentMachine): List<DemoAgentStep> =
        DemoAgentStreams.steps(path, request, machine)
            ?: DemoAgentJobs.steps(path, request, machine)
            ?: emptyList()

    /** Which services this machine still carries */
    fun present(machine: DemoAgentMachine): List<String> {
        val removed = DemoFleetState.removed(machine)
        return machine.containers.filter { it !in removed }
    }

    /** Whether the machine says a service is running */
    fun isRunning(id: String, machine: DemoAgentMachine): Boolean =
        id !in DemoFleetState.stopped(machine) && id !in DemoFleetState.removed(machine)

    fun progressLines(subject: String, verb: String): List<String> = listOf(
        "==> $verb $subject",
        "Pulling images…",
        "Creating containers…",
        "Waiting for the health check…",
        "$subject: done",
    )
}
