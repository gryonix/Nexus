package com.skaymer.gryonixnexus.catalog

/** A service's rough minimum resource footprint */
data class ServiceResources(
    /** RAM the running containers need, in mebibytes */
    val memoryMB: Int,
    /** On-disk footprint — images plus a little data headroom, in gibibytes */
    val diskGB: Int
)

data class ServerRequirements(
    /** Total RAM floor incl */
    val memoryMB: Int,
    /** Total free-disk floor incl */
    val diskGB: Int,
    val installsDocker: Boolean
) {
    /** RAM rounded up to whole gibibytes for display */
    val memoryGB: Int get() = Math.ceil(memoryMB / 1024.0).toInt()
}

/** How the service runs on the server */
sealed class ServiceRuntime {
    data class Docker(val composeProject: String) : ServiceRuntime()
}

/** A file the setup script writes for a docker service */
data class ComposeFile(
    /** e.g */
    val directory: String,
    /** docker-compose.yml body */
    val composeContents: String,
    /** Optional .env written next to the compose file */
    val envTemplate: String? = null
)

data class ServiceRecord(
    /** The full record name, e.g */
    val name: String,
    val priority: Int = 0,
    val weight: Int = 5,
    val port: Int,
    /** The host that answers, without a trailing dot */
    val target: String
)

data class FirewallPort(
    val port: Int,
    val proto: Proto = Proto.TCP,
    val comment: String
) {
    enum class Proto(val wireValue: String) { TCP("tcp"), UDP("udp") }
}

/** HTTP endpoint published via the shared Caddy ingress */
data class WebIngress(
    val hostname: String,
    val upstreamPort: Int,
    val adminGuard: Boolean = true,
    val upstreamHTTPS: Boolean = false,
    val publicPaths: List<String> = emptyList(),
    val overwriteForwardedFor: Boolean = false
)
