package com.skaymer.gryonixnexus.app.servers.demo

import gryonixnexusd.v1.SecurityAllowlist
import gryonixnexusd.v1.SecurityAllowlistEntry
import gryonixnexusd.v1.SecurityAutoRules
import gryonixnexusd.v1.SecurityBan
import gryonixnexusd.v1.SecurityDecision
import gryonixnexusd.v1.SecurityDecisions
import gryonixnexusd.v1.SecurityScenario
import gryonixnexusd.v1.SecurityStatus
import gryonixnexusd.v1.SetSecurityAllowlistRequest
import gryonixnexusd.v1.SetSecurityAutoRulesRequest
import gryonixnexusd.v1.SetSecurityDecisionRequest
import gryonixnexusd.v1.SetSshKeyOnlyUsersRequest
import gryonixnexusd.v1.SetSshPasswordLoginRequest
import gryonixnexusd.v1.SshPasswordState
import gryonixnexusd.v1.SshUser
import gryonixnexusd.v1.SshUsers
import kotlin.random.Random

/** Intrusion defence and SSH access */
object DemoAgentSecurity {
    private val sshClientIPs = listOf("198.51.100.9")

    fun answer(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Security/GetSecurityStatus" ->
            DemoAgentState.memory(machine) { status(it.bans) }.demoPayload()
        "/gryonixnexusd.v1.Security/GetSshPasswordState" -> sshState(machine).demoPayload()
        "/gryonixnexusd.v1.Security/SetSshPasswordLogin" -> {
            val asked = SetSshPasswordLoginRequest.ADAPTER.decode(request)
            DemoAgentState.memory(machine) { it.passwordLoginOpen = asked.allow_passwords }
            sshState(machine).demoPayload()
        }
        "/gryonixnexusd.v1.Security/ListSshUsers", "/gryonixnexusd.v1.Security/AuthorizeAppKey" ->
            sshUsers(machine).demoPayload()
        "/gryonixnexusd.v1.Security/SetSshKeyOnlyUsers" -> {
            val asked = SetSshKeyOnlyUsersRequest.ADAPTER.decode(request)
            DemoAgentState.memory(machine) {
                it.keyOnlyUsers = (if (asked.everyone) accounts(machine) else asked.users).toMutableSet()
                it.passwordLoginOpen = !asked.everyone
            }
            sshUsers(machine).demoPayload()
        }
        else -> decisions(path, request, machine)
    }

    // SSH accounts

    private fun accounts(machine: DemoAgentMachine) = listOf(machine.deployment.dashboardConfig.sshUser, "root", "backup")

    private fun sshState(machine: DemoAgentMachine): SshPasswordState = DemoAgentState.memory(machine) {
        SshPasswordState(
            password_login_open = it.passwordLoginOpen,
            known = true,
            app_key_present = true,
            drop_in_present = true,
            sshd_present = true,
            login_user = machine.deployment.dashboardConfig.sshUser,
        )
    }

    private fun sshUsers(machine: DemoAgentMachine): SshUsers {
        val login = machine.deployment.dashboardConfig.sshUser
        val host = sshState(machine)
        return DemoAgentState.memory(machine) { stored ->
            SshUsers(
                known = true,
                host = host,
                users = accounts(machine).map { name ->
                    SshUser(
                        name = name,
                        known = true,
                        is_login_user = name == login,
                        carries_keys = name !in stored.lockedOutUsers,
                        app_key_present = name == login,
                        password_login_open = name !in stored.keyOnlyUsers,
                    )
                },
            )
        }
    }

    // Blocked and allowed addresses

    private fun decisions(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Security/GetSecurityDecisions" -> decisionList(machine).demoPayload()
        "/gryonixnexusd.v1.Security/SetSecurityDecision" -> {
            val asked = SetSecurityDecisionRequest.ADAPTER.decode(request)
            DemoAgentState.memory(machine) { stored ->
                if (asked.banned) stored.bans.add(0, handMade(asked))
                else stored.bans.removeAll { it.value == asked.value_ || it.id == asked.id }
            }
            decisionList(machine).demoPayload()
        }
        "/gryonixnexusd.v1.Security/GetSecurityAllowlist" -> allowlist(machine).demoPayload()
        "/gryonixnexusd.v1.Security/SetSecurityAllowlist" -> {
            val asked = SetSecurityAllowlistRequest.ADAPTER.decode(request)
            DemoAgentState.memory(machine) { stored ->
                stored.allowlist.removeAll { it.value == asked.value_ }
                if (asked.allowed) {
                    stored.allowlist.add(DemoAgentState.Allowed(asked.value_, asked.comment))
                    stored.bans.removeAll { it.value == asked.value_ }
                }
            }
            allowlist(machine).demoPayload()
        }
        else -> autoRules(path, request, machine)
    }

    private fun decisionList(machine: DemoAgentMachine) = DemoAgentState.memory(machine) { stored ->
        SecurityDecisions(
            present = true,
            community_count = 17_707,
            ssh_client_ips = sshClientIPs,
            decisions = stored.bans.map { ban ->
                SecurityDecision(
                    id = ban.id, scope = ban.scope, value_ = ban.value, action = "ban", reason = ban.reason,
                    country = ban.country, as_name = ban.asName, source = ban.source,
                    expires_in = ban.expiresIn, events = ban.events,
                )
            },
        )
    }

    /** A ban somebody made from the app */
    private fun handMade(asked: SetSecurityDecisionRequest) = DemoAgentState.Ban(
        id = "${Random.nextInt(300_000, 400_000)}",
        scope = if ("/" in asked.value_) "Range" else "Ip",
        value = asked.value_,
        reason = asked.reason.ifEmpty { "gryonixnexus: added by hand" },
        country = "", asName = "", source = "cscli",
        expiresIn = readable(asked.duration_seconds), events = 1,
    )

    private fun readable(seconds: Long): String {
        if (seconds <= 0) return ""
        val hours = seconds / 3_600
        val minutes = (seconds % 3_600) / 60
        return if (minutes == 0L) "${hours}h" else "${hours}h${minutes}m"
    }

    private fun allowlist(machine: DemoAgentMachine) = DemoAgentState.memory(machine) { stored ->
        SecurityAllowlist(
            present = true,
            supported = true,
            name = "gryonixnexus",
            ssh_client_ips = sshClientIPs,
            entries = stored.allowlist.map { SecurityAllowlistEntry(value_ = it.value, comment = it.comment) },
        )
    }

    private fun autoRules(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Security/GetSecurityAutoRules" -> rules(machine).demoPayload()
        "/gryonixnexusd.v1.Security/SetSecurityAutoRules" -> {
            val asked = SetSecurityAutoRulesRequest.ADAPTER.decode(request).rules
            DemoAgentState.memory(machine) {
                it.autoRulesEnabled = asked?.enabled ?: false
                it.autoRuleCountries = asked?.countries.orEmpty()
            }
            rules(machine).demoPayload()
        }
        else -> null
    }

    private fun rules(machine: DemoAgentMachine) = DemoAgentState.memory(machine) {
        SecurityAutoRules(
            enabled = it.autoRulesEnabled,
            countries = it.autoRuleCountries,
            attempt_threshold = 5,
            attempt_window_minutes = 10,
            ban_subnet = false,
            ban_seconds = 14_400,
            geoip_available = true,
        )
    }

    /** What the defence reports */
    fun status(bans: List<DemoAgentState.Ban>, present: Boolean = true, running: Boolean = true) = SecurityStatus(
        present = present,
        engine_running = running,
        bouncer_running = true,
        engine_version = "v1.8.1",
        alerts_24h = 49,
        local_bans = bans.size,
        community_blocklist_ips = 17_707,
        packets_dropped = 17_800,
        top_scenarios = listOf(SecurityScenario(name = "crowdsecurity/ssh-bf", count = 37)),
        recent_bans = bans.take(3).map { held ->
            SecurityBan(
                ip = held.value,
                country = held.country.ifEmpty { "RU" },
                scenario = held.reason,
                at = "2026-09-12T15:52:20Z",
            )
        },
    )
}
