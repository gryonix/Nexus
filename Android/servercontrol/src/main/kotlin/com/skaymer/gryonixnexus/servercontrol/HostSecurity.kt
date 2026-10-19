package com.skaymer.gryonixnexus.servercontrol

data class HostSecurityStatus(
    val isPresent: Boolean,
    val engineRunning: Boolean,
    val bouncerRunning: Boolean,
    /** e.g */
    val engineVersion: String,
    val alertsLast24h: Int,
    val localBans: Int,
    val communityBlocklistIps: Int,
    val packetsDropped: Long,
    val topScenarios: List<Scenario>,
    val recentBans: List<Ban>,
) {
    data class Scenario(val name: String, val count: Int) {
        val readableName: String
            get() {
                val tail = name.substringAfterLast('/')
                return when (tail) {
                    "ssh-bf", "ssh-bf_user-enum" -> "SSH brute force"
                    "ssh-slow-bf", "ssh-slow-bf_user-enum" -> "SSH slow brute force"
                    "ssh-time-based-bf", "ssh-time-based-bf_user-enum" -> "SSH timed brute force"
                    "ssh-cve-2024-6387" -> "SSH regreSSHion probe (CVE-2024-6387)"
                    "http-bf", "http-generic-bf" -> "Web login brute force"
                    "http-crawl-non_statics" -> "Aggressive web crawling"
                    "http-probing" -> "Web path probing"
                    "http-sensitive-files" -> "Sensitive-file scanning"
                    else -> tail.replace('_', ' ').replace('-', ' ')
                        .split(' ').joinToString(" ") { w ->
                            w.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
                        }
                }
            }
    }

    data class Ban(
        val ip: String,
        /** Two-letter country code, or "" when CrowdSec could not place it */
        val country: String,
        val scenario: String,
        /** CrowdSec's own RFC 3339 timestamp string, or "" if absent */
        val at: String,
    )

    /** Protection is in place and both halves are up */
    val isHealthy: Boolean get() = isPresent && engineRunning && bouncerRunning

    companion object {
        val UNKNOWN = HostSecurityStatus(
            isPresent = false,
            engineRunning = false,
            bouncerRunning = false,
            engineVersion = "",
            alertsLast24h = 0,
            localBans = 0,
            communityBlocklistIps = 0,
            packetsDropped = 0,
            topScenarios = emptyList(),
            recentBans = emptyList(),
        )
    }
}

data class SshPasswordAccess(
    /** sshd accepts passwords right now */
    val passwordLoginOpen: Boolean,
    val isKnown: Boolean,
    val appKeyPresent: Boolean,
    /** This product's drop-in is on disk */
    val dropInPresent: Boolean,
    val sshdPresent: Boolean,
    val loginUser: String,
    val detail: String,
) {
    /** The host said what it accepts and it accepts passwords */
    val isOpen: Boolean get() = isKnown && passwordLoginOpen

    /** The host said what it accepts and it refuses them */
    val isClosed: Boolean get() = isKnown && !passwordLoginOpen

    val canClose: Boolean get() = isOpen && appKeyPresent

    val isOutranked: Boolean get() = isKnown && passwordLoginOpen && dropInPresent

    companion object {
        val UNKNOWN = SshPasswordAccess(
            passwordLoginOpen = false,
            isKnown = false,
            appKeyPresent = false,
            dropInPresent = false,
            sshdPresent = false,
            loginUser = "",
            detail = "",
        )
    }
}

data class HostSecurityDecisions(
    val isPresent: Boolean,
    val decisions: List<Decision>,
    /** How many addresses the COMMUNITY blocklist is blocking */
    val communityCount: Int,
    val sshClientIps: List<String>,
) {
    data class Decision(
        val decisionId: String,
        /** "Ip", "Range", "Country" — CrowdSec's own word */
        val scope: String,
        val value: String,
        val action: String,
        val reason: String,
        val country: String,
        val asName: String,
        val source: String,
        val expiresIn: String,
        val events: Int,
    ) {
        val id: String get() = decisionId.ifEmpty { "$source|$value" }

        val isManual: Boolean get() = source == "cscli"

        val readableReason: String
            get() = if (!reason.contains('/')) reason
            else HostSecurityStatus.Scenario(name = reason, count = 0).readableName
    }

    companion object {
        val UNKNOWN = HostSecurityDecisions(
            isPresent = false,
            decisions = emptyList(),
            communityCount = 0,
            sshClientIps = emptyList(),
        )
    }
}

/** The addresses this host will never ban */
data class HostSecurityAllowlist(
    val isPresent: Boolean,
    val isSupported: Boolean,
    val name: String,
    val entries: List<Entry>,
    /** Same list, and same reason, as [HostSecurityDecisions.sshClientIps] */
    val sshClientIps: List<String>,
) {
    data class Entry(
        val value: String,
        val comment: String,
        /** As CrowdSec prints it; empty when the entry never expires */
        val expiresIn: String,
    )

    fun allows(value: String): Boolean = entries.any { it.value == value }

    companion object {
        val UNKNOWN = HostSecurityAllowlist(
            isPresent = false,
            isSupported = false,
            name = "",
            entries = emptyList(),
            sshClientIps = emptyList(),
        )
    }
}

data class HostSecurityAutoRules(
    val isOn: Boolean = false,
    /** ISO 3166-1 alpha-2 codes, as CrowdSec enriches them */
    val countries: List<String> = emptyList(),
    val countriesAreAllowlist: Boolean = false,
    /** N failures is an attack */
    val attemptThreshold: Int = 0,
    val attemptWindowMinutes: Int = 0,
    /** Ban the neighbourhood rather than the address — `/24` for IPv4 */
    val bansSubnet: Boolean = false,
    /** How long a ban from these rules lasts */
    val banSeconds: Long = 0,
    /** Per-service sharpening: SSH answered harder than a web form */
    val services: List<ServiceRule> = emptyList(),
    val geoIPAvailable: Boolean = false,
) {
    data class ServiceRule(
        /** The scenario family this sharpens — "ssh", "http", "smtp" */
        val service: String,
        val attemptThreshold: Int = 0,
        val banSeconds: Long = 0,
    )

    /** Whether these orders say anything at all */
    val isEmpty: Boolean
        get() = countries.isEmpty() && attemptThreshold == 0 && services.isEmpty()
}
