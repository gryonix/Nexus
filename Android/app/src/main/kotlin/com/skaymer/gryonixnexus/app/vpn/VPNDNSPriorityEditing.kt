package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.agentcontrol.VPNDNSPriority

/** Edits of the DNS relay's resolver order */
object VPNDNSPriorityEditing {
    const val MAX_RESOLVERS = 4

    /** Public resolvers offered for the order, by first address */
    val publicChoices: List<PublicDNS> =
        PublicDNS.all.filter { it.variant == null }.distinctBy { it.provider }

    fun moveUp(index: Int, order: List<String>): List<String> {
        if (index !in order.indices || index == 0) return order
        return order.toMutableList().apply { add(index - 1, removeAt(index)) }
    }

    fun moveDown(index: Int, order: List<String>): List<String> {
        if (index !in order.indices || index == order.lastIndex) return order
        return order.toMutableList().apply { add(index + 1, removeAt(index)) }
    }

    /** The order without this entry; the last one stays */
    fun remove(index: Int, order: List<String>): List<String> {
        if (index !in order.indices || order.size <= 1) return order
        return order.filterIndexed { position, _ -> position != index }
    }

    /** The order with one more resolver at the end */
    fun add(entry: String, order: List<String>): List<String> {
        val clean = entry.trim()
        if (clean.isEmpty() || clean in order || order.size >= MAX_RESOLVERS) return order
        return order + clean
    }

    fun canAdd(order: List<String>): Boolean = order.size < MAX_RESOLVERS

    /** One typed address, else null */
    fun typed(text: String): String? = PublicDNS.parse(text)?.singleOrNull()

    /** What one entry stands for, before it is named */
    fun describe(entry: String): Entry {
        if (entry == VPNDNSPriority.LOCAL) return Entry.Local
        val preset = PublicDNS.all.firstOrNull { entry in it.addresses } ?: return Entry.Address(entry)
        return Entry.Preset(preset, entry)
    }

    sealed interface Entry {
        data object Local : Entry

        data class Preset(val preset: PublicDNS, val address: String) : Entry

        data class Address(val address: String) : Entry
    }
}
