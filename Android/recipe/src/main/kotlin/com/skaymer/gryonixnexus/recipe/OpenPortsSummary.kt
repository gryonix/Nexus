package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.FirewallPort
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.core.WireGuardDefaults

data class OpenPortRequirement(
    val port: Int,
    val proto: Proto,
    /** Who needs the port — "Mailcow (SMTP)", "SSH", … — joined when shared */
    val purpose: String
) {
    enum class Proto(val label: String) { TCP("TCP"), UDP("UDP") }

    val id: String get() = "$port/${proto.label}"
}

fun List<OpenPortRequirement>.sortedByPort(): List<OpenPortRequirement> =
    sortedWith(compareBy({ it.port }, { it.proto.label }))

fun List<OpenPortRequirement>.sortedByProtocol(): List<OpenPortRequirement> =
    sortedWith(compareBy({ it.proto.label }, { it.port }))

object OpenPortsSummary {
    private data class Key(val port: Int, val proto: OpenPortRequirement.Proto)

    fun entryHostPorts(input: MailRecipeInput): List<OpenPortRequirement> {
        val context = MailContext(input)
        val purposes = LinkedHashMap<Key, MutableList<String>>()
        fun add(port: Int, proto: OpenPortRequirement.Proto, purpose: String) {
            val list = purposes.getOrPut(Key(port, proto)) { mutableListOf() }
            if (purpose !in list) list.add(purpose)
        }

        add(input.security.ssh.port, OpenPortRequirement.Proto.TCP, "SSH")
        if (input.topology == Topology.VPS_RELAY_WITH_HOME_BACKEND) {
            add(WireGuardDefaults.LISTEN_PORT, OpenPortRequirement.Proto.UDP,
                "WireGuard (VPS ↔ home)")
        }
        add(80, OpenPortRequirement.Proto.TCP, "HTTP / ACME")
        if (context.needsCaddy) add(443, OpenPortRequirement.Proto.TCP, "HTTPS")
        for (service in context.allSelectedServices) {
            for (firewallPort in service.firewallPorts(context.serviceContext)) {
                val proto = if (firewallPort.proto == FirewallPort.Proto.UDP) {
                    OpenPortRequirement.Proto.UDP
                } else {
                    OpenPortRequirement.Proto.TCP
                }
                val purpose = if (firewallPort.comment.isEmpty() ||
                    firewallPort.comment == service.displayName) {
                    service.displayName
                } else {
                    "${service.displayName} (${firewallPort.comment})"
                }
                add(firewallPort.port, proto, purpose)
            }
        }

        return purposes
            .map { (key, names) ->
                OpenPortRequirement(key.port, key.proto, names.joinToString(", "))
            }
            .sortedWith(compareBy({ it.port }, { it.proto.label }))
    }
}
