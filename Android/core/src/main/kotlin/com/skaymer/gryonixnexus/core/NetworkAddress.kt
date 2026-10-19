package com.skaymer.gryonixnexus.core

sealed class NetworkAddress(val value: String) {
    class IPv4(value: String) : NetworkAddress(value)
    class IPv6(value: String) : NetworkAddress(value)

    class Hostname(value: String) : NetworkAddress(value)

    val isIPv4: Boolean get() = this is IPv4

    override fun toString(): String = value
    override fun equals(other: Any?): Boolean =
        other is NetworkAddress && other.javaClass == javaClass && other.value == value
    override fun hashCode(): Int = 31 * javaClass.hashCode() + value.hashCode()

    companion object {
        /** Parses a string, throwing [ValidationError.InvalidAddress] on an invalid format */
        fun parse(string: String): NetworkAddress {
            val trimmed = string.trim()
            return when {
                isValidIPv4(trimmed) -> IPv4(trimmed)
                isValidIPv6(trimmed) -> IPv6(trimmed.lowercase())
                else -> throw ValidationError.InvalidAddress(string)
            }
        }

        fun parseOrNull(string: String): NetworkAddress? =
            runCatching { parse(string) }.getOrNull()

        fun localOnly(string: String): NetworkAddress {
            val trimmed = string.trim()
            parseOrNull(trimmed)?.let { return it }
            val lowered = trimmed.lowercase()
            if (Domain.isValid(lowered)) return Hostname(lowered)
            throw ValidationError.InvalidAddress(string)
        }

        fun isValidIPv4(candidate: String): Boolean {
            val octets = candidate.split(".")
            if (octets.size != 4) return false
            return octets.all { octet ->
                if (octet.isEmpty() || octet.length > 3 || !octet.all { it.isDigit() }) return@all false
                // Disallow leading zeros ("01"), but allow a lone "0".
                if (octet.length != 1 && octet.first() == '0') return@all false
                (octet.toIntOrNull() ?: return@all false) <= 255
            }
        }

        fun isValidIPv6(candidate: String): Boolean {
            // Deliberately a loose check: hex groups and colons.
            if (!candidate.contains(":") || candidate.length < 2 || candidate.length > 45) return false
            return candidate.all { it in "0123456789abcdefABCDEF:" }
        }
    }
}
