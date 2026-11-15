package com.skaymer.gryonixnexus.profile.advanced

import java.util.UUID
import kotlinx.serialization.Serializable

enum class ServerKind { VLESS, VMESS, TROJAN, SHADOWSOCKS, WIREGUARD, HYSTERIA2, NAIVE }

@Serializable
data class AdvancedServer(
    val id: String,
    val name: String,
    val kind: ServerKind,
    val host: String,
    val port: Int,
    /** Protocol settings by name: uuid, password, method, network, sni... */
    val fields: Map<String, String>,
) {
    companion object {
        fun create(kind: ServerKind, name: String, host: String, port: Int, fields: Map<String, String>) =
            AdvancedServer(identity(kind, host, port, fields), name.ifEmpty { host }, kind, host, port, fields)

        fun identity(kind: ServerKind, host: String, port: Int, fields: Map<String, String>): String {
            val secret = fields["uuid"] ?: fields["password"] ?: fields["secretKey"] ?: ""
            return "${kind.name.lowercase()}-$host:$port-${fnv(secret)}"
        }

        fun fnv(text: String): String {
            var hash = 2_166_136_261L
            for (byte in text.toByteArray(Charsets.UTF_8)) {
                hash = ((hash xor (byte.toLong() and 0xFF)) * 16_777_619L) and 0xFFFFFFFFL
            }
            return hash.toString(16)
        }
    }
}

enum class RuleKind { DOMAIN, DOMAIN_SUFFIX, KEYWORD, IP, GEOIP }

enum class RuleAction { DIRECT, PROXY, BLOCK }

@Serializable
data class AdvancedRule(
    val kind: RuleKind,
    val value: String,
    val action: RuleAction,
    val id: String = UUID.randomUUID().toString(),
)

enum class GroupMode { AUTO, MANUAL }

@Serializable
data class AdvancedGroup(
    val name: String,
    val mode: GroupMode,
    val memberIDs: List<String>,
    val selectedID: String? = null,
    val id: String = UUID.randomUUID().toString(),
) {
    /** The member a manual group sends traffic to */
    val chosenID: String? get() = selectedID?.takeIf { it in memberIDs } ?: memberIDs.firstOrNull()
}

enum class DnsKind { PLAIN, TCP, DOH, DOQ, DOT }

@Serializable
data class AdvancedDnsUpstream(
    val kind: DnsKind,
    val address: String,
    /** Only these domains use this upstream; empty means all */
    val domains: List<String> = emptyList(),
    val viaProxy: Boolean = true,
    val id: String = UUID.randomUUID().toString(),
)

@Serializable
data class AdvancedBlockList(
    val url: String,
    val domains: List<String> = emptyList(),
    val updatedAtMillis: Long? = null,
    val id: String = UUID.randomUUID().toString(),
)

@Serializable
data class AdvancedSubscription(
    val name: String,
    val url: String,
    val serverIDs: List<String> = emptyList(),
    val updatedAtMillis: Long? = null,
    val id: String = UUID.randomUUID().toString(),
)

@Serializable
data class AdvancedProfile(
    val servers: List<AdvancedServer> = emptyList(),
    val groups: List<AdvancedGroup> = emptyList(),
    val rules: List<AdvancedRule> = emptyList(),
    val finalAction: RuleAction = RuleAction.PROXY,
    val dns: List<AdvancedDnsUpstream> = emptyList(),
    val blockLists: List<AdvancedBlockList> = emptyList(),
    val subscriptions: List<AdvancedSubscription> = emptyList(),
    /** A server id or a group id */
    val activeID: String? = null,
    val collectsTraffic: Boolean = false,
    val geoip: AdvancedGeoIP = AdvancedGeoIP(),
    val hosts: List<AdvancedHostRewrite> = emptyList(),
    /** Host rewrites apply only when this is on */
    val rewritesEnabled: Boolean = false,
) {
    fun server(id: String): AdvancedServer? = servers.firstOrNull { it.id == id }
    fun group(id: String): AdvancedGroup? = groups.firstOrNull { it.id == id }

    /** The group or server the tunnel runs */
    val activeGroup: AdvancedGroup? get() = activeID?.let { group(it) }
    val activeServer: AdvancedServer? get() = activeID?.let { if (group(it) == null) server(it) else null }

    fun removing(serverIDs: Set<String>): AdvancedProfile {
        val kept = copy(
            servers = servers.filter { it.id !in serverIDs },
            groups = groups.map { it.copy(memberIDs = it.memberIDs.filter { id -> id !in serverIDs }) },
        )
        val active = kept.activeID
        return if (active != null && kept.server(active) == null && kept.group(active) == null) {
            kept.copy(activeID = null)
        } else {
            kept
        }
    }

    /** Adds or replaces servers by id, keeping order */
    fun merging(incoming: List<AdvancedServer>): AdvancedProfile {
        val merged = servers.toMutableList()
        for (server in incoming) {
            val index = merged.indexOfFirst { it.id == server.id }
            if (index >= 0) merged[index] = server else merged.add(server)
        }
        return copy(servers = merged)
    }
}

/** What an import understood and what it left out. */
data class AdvancedImportReport(
    val servers: List<AdvancedServer> = emptyList(),
    val rules: List<AdvancedRule> = emptyList(),
    val unsupported: List<Skipped> = emptyList(),
) {
    data class Skipped(val name: String, val reason: String)

    val isEmpty: Boolean get() = servers.isEmpty() && rules.isEmpty()
}
