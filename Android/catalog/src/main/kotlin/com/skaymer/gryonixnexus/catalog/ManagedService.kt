package com.skaymer.gryonixnexus.catalog

interface ManagedService {
    val id: ServiceID
    val displayName: String
    val systemImage: String

    /** Which shelf of the catalog this service sits on */
    val category: ServiceCategory

    /** Which shelf this service's ROW groups under on screen */
    val displayCategory: ServiceCategory get() = category

    val runtime: ServiceRuntime

    /** Services that cannot coexist with this one (e.g */
    val conflicts: Set<ServiceID>
        get() {
            if (category.selection != ServiceCategory.Selection.EXCLUSIVE) return emptySet()
            return ServiceRegistry.all
                .filter { it.category == category && it.id != id }
                .map { it.id }
                .toSet()
        }

    val usesSharedAdminLogin: Boolean get() = false

    val resources: ServiceResources get() = ServiceResources(memoryMB = 128, diskGB = 1)

    val requiresPublicDomain: Boolean get() = false

    /** Only installable on a machine inside the house */
    val requiresHomeMachine: Boolean get() = false

    // ---------------------------------------------------------------- Generation

    /** docker-compose.yml (+ optional .env) to install; null for systemd services */
    fun composeFile(context: ServiceContext): ComposeFile?

    fun setupSteps(context: ServiceContext): List<String>

    fun firewallPorts(context: ServiceContext): List<FirewallPort>

    /** HTTP endpoint to publish through the shared Caddy ingress */
    fun webIngress(context: ServiceContext): WebIngress?

    /** Additional DNS A-records (custom hostnames) pointing at the entry IP */
    fun dnsHostnames(context: ServiceContext): List<String>

    fun serviceRecords(context: ServiceContext): List<ServiceRecord> = emptyList()

    fun reportSteps(context: ServiceContext): List<String> = emptyList()

    // ---------------------------------------------------------------- Management

    fun actions(context: ServiceContext): ServiceActions

    fun updateSpec(context: ServiceContext): UpdateSpec

    fun extraSudoers(context: ServiceContext): List<PrivilegedCommand> = emptyList()

    /** How this service is removed */
    fun uninstallSpec(context: ServiceContext): UninstallSpec {
        val project = (runtime as? ServiceRuntime.Docker)?.composeProject
        return UninstallSpec(composeProject = project,
                             configDirectory = composeFile(context)?.directory)
    }

    fun sudoersLines(context: ServiceContext): List<String> {
        val actions = actions(context)
        val commands = buildList {
            addAll(actions.statusProbe.privilegedCommands)
            actions.restart?.let { add(it.privileged) }
            actions.start?.let { add(it.privileged) }
            actions.stop?.let { add(it.privileged) }
            actions.backup?.let { addAll(it.privilegedCommands(context)) }
            actions.restore?.let { add(it.privileged) }
            actions.logs?.let { add(it.privileged) }
            addAll(extraSudoers(context))
        }
        val seen = LinkedHashSet<PrivilegedCommand>()
        return commands.filter { seen.add(it) }.map { it.sudoersLine(context.sshUser) }
    }
}

interface MailEngineService : ManagedService {
    /** The mail hostname this engine mandates (e.g */
    fun requiredHostname(domain: String): String? = null

    override val requiresPublicDomain: Boolean get() = true
}

/** The ports a relay carries in from the internet */
object ForwardedPorts {
    /** DNS serves the home network, never the internet */
    private val homeOnlyPorts = setOf(53)

    fun tcp(services: List<ManagedService>, context: ServiceContext): List<Int> {
        val ports = sortedSetOf(80)
        if (services.any { it.webIngress(context) != null }) ports.add(443)
        ports += carried(services, context, FirewallPort.Proto.TCP)
        return ports.toList()
    }

    fun udp(services: List<ManagedService>, context: ServiceContext): List<Int> =
        carried(services, context, FirewallPort.Proto.UDP).sorted()

    private fun carried(services: List<ManagedService>, context: ServiceContext, proto: FirewallPort.Proto): Set<Int> =
        services.filter { !it.requiresHomeMachine }
            .flatMap { it.firewallPorts(context) }
            .filter { it.proto == proto && it.port !in homeOnlyPorts }
            .map { it.port }
            .toSet()
}
