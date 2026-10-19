package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.servercontrol.HostSecurityAllowlist
import com.skaymer.gryonixnexus.servercontrol.HostSecurityAutoRules
import com.skaymer.gryonixnexus.servercontrol.HostSecurityDecisions
import com.skaymer.gryonixnexus.servercontrol.HostSecurityStatus
import com.skaymer.gryonixnexus.servercontrol.SshPasswordAccess
import gryonixnexusd.v1.SecurityAction
import gryonixnexusd.v1.SecurityAllowlist
import gryonixnexusd.v1.SecurityDecisions
import gryonixnexusd.v1.SecurityStatus
import gryonixnexusd.v1.ServiceOperationPhase
import gryonixnexusd.v1.SshPasswordState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.mapNotNull

class AgentSecurityOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) {
    suspend fun status(): HostSecurityStatus =
        agentFailure("security") { statusFrom(gate.gated { client.getSecurityStatus() }) }

    suspend fun sshPasswordAccess(loginUser: String, appPublicKey: String): SshPasswordAccess =
        agentFailure("security") {
            accessFrom(gate.gated { client.getSSHPasswordState(loginUser, appPublicKey) })
        }

    /** Close SSH password login, or allow it again */
    suspend fun setSshPasswordLogin(
        open: Boolean,
        loginUser: String,
        appPublicKey: String,
    ): SshPasswordAccess =
        agentFailure("security") {
            accessFrom(gate.gated { client.setSSHPasswordLogin(open, loginUser, appPublicKey) })
        }

    enum class Action {
        START, STOP, RESTART, UPDATE, INSTALL, REMOVE;

        internal val proto: SecurityAction
            get() = when (this) {
                START -> SecurityAction.SECURITY_ACTION_START
                STOP -> SecurityAction.SECURITY_ACTION_STOP
                RESTART -> SecurityAction.SECURITY_ACTION_RESTART
                UPDATE -> SecurityAction.SECURITY_ACTION_UPDATE
                INSTALL -> SecurityAction.SECURITY_ACTION_INSTALL
                REMOVE -> SecurityAction.SECURITY_ACTION_REMOVE
            }

        val isDestructive: Boolean get() = this == REMOVE || this == STOP
    }

    /** One progress line of a running operation, or its result */
    sealed interface Progress {
        /** A line the command printed, exactly as it printed it */
        data class Line(val text: String) : Progress
        data class Finished(val status: HostSecurityStatus) : Progress
    }

    fun control(action: Action): Flow<Progress> =
        client.controlSecurity(action.proto).mapNotNull { event ->
            when (event.phase) {
                ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS ->
                    event.text.trim().takeIf { it.isNotEmpty() }?.let { Progress.Line(it) }
                ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED ->
                    Progress.Finished(statusFrom(event.status ?: SecurityStatus()))
                else -> null
            }
        }

    /** Who the host is blocking right now */
    suspend fun decisions(): HostSecurityDecisions =
        agentFailure("security") { decisionsFrom(gate.gated { client.getSecurityDecisions() }) }

    /** Ban an address by hand, or lift a ban */
    suspend fun setBan(
        banned: Boolean,
        value: String,
        decisionId: String = "",
        durationSeconds: Long = 0,
        reason: String = "",
    ): HostSecurityDecisions =
        agentFailure("security") {
            decisionsFrom(
                gate.gated {
                    client.setSecurityDecision(value, banned, decisionId, durationSeconds, reason)
                },
            )
        }

    suspend fun autoRules(): HostSecurityAutoRules =
        agentFailure("security") { autoRulesFrom(gate.gated { client.getSecurityAutoRules() }) }

    suspend fun setAutoRules(rules: HostSecurityAutoRules): HostSecurityAutoRules =
        agentFailure("security") {
            autoRulesFrom(
                gate.gated {
                    client.setSecurityAutoRules(
                        gryonixnexusd.v1.SecurityAutoRules(
                            enabled = rules.isOn,
                            countries = rules.countries,
                            countries_are_allowlist = rules.countriesAreAllowlist,
                            attempt_threshold = maxOf(rules.attemptThreshold, 0),
                            attempt_window_minutes = maxOf(rules.attemptWindowMinutes, 0),
                            ban_subnet = rules.bansSubnet,
                            ban_seconds = maxOf(rules.banSeconds, 0),
                            services = rules.services.map {
                                gryonixnexusd.v1.SecurityServiceRule(
                                    service = it.service,
                                    attempt_threshold = maxOf(it.attemptThreshold, 0),
                                    ban_seconds = maxOf(it.banSeconds, 0),
                                )
                            },
                        ),
                    )
                },
            )
        }

    /** The addresses this host will never ban */
    suspend fun allowlist(): HostSecurityAllowlist =
        agentFailure("security") { allowlistFrom(gate.gated { client.getSecurityAllowlist() }) }

    /** Put an address beyond banning, or stop protecting it */
    suspend fun setAllowed(
        allowed: Boolean,
        value: String,
        comment: String = "",
        durationSeconds: Long = 0,
    ): HostSecurityAllowlist =
        agentFailure("security") {
            allowlistFrom(gate.gated { client.setSecurityAllowlist(value, allowed, comment, durationSeconds) })
        }

    companion object {
        fun decisionsFrom(proto: SecurityDecisions): HostSecurityDecisions = HostSecurityDecisions(
            isPresent = proto.present,
            decisions = proto.decisions.map {
                HostSecurityDecisions.Decision(
                    decisionId = it.id,
                    scope = it.scope,
                    value = it.value_,
                    action = it.action,
                    reason = it.reason,
                    country = it.country,
                    asName = it.as_name,
                    source = it.source,
                    expiresIn = it.expires_in,
                    events = it.events,
                )
            },
            communityCount = proto.community_count,
            sshClientIps = proto.ssh_client_ips,
        )

        /** The wire's standing orders as the app's own type */
        fun autoRulesFrom(proto: gryonixnexusd.v1.SecurityAutoRules) = HostSecurityAutoRules(
            isOn = proto.enabled,
            countries = proto.countries,
            countriesAreAllowlist = proto.countries_are_allowlist,
            attemptThreshold = proto.attempt_threshold,
            attemptWindowMinutes = proto.attempt_window_minutes,
            bansSubnet = proto.ban_subnet,
            banSeconds = proto.ban_seconds,
            services = proto.services.map {
                HostSecurityAutoRules.ServiceRule(it.service, it.attempt_threshold, it.ban_seconds)
            },
            geoIPAvailable = proto.geoip_available,
        )

        fun allowlistFrom(proto: SecurityAllowlist): HostSecurityAllowlist = HostSecurityAllowlist(
            isPresent = proto.present,
            isSupported = proto.supported,
            name = proto.name,
            entries = proto.entries.map {
                HostSecurityAllowlist.Entry(
                    value = it.value_,
                    comment = it.comment,
                    expiresIn = it.expires_in,
                )
            },
            sshClientIps = proto.ssh_client_ips,
        )

        fun accessFrom(proto: SshPasswordState): SshPasswordAccess = SshPasswordAccess(
            passwordLoginOpen = proto.password_login_open,
            isKnown = proto.known,
            appKeyPresent = proto.app_key_present,
            dropInPresent = proto.drop_in_present,
            sshdPresent = proto.sshd_present,
            loginUser = proto.login_user,
            detail = proto.detail,
        )

        fun statusFrom(proto: SecurityStatus): HostSecurityStatus = HostSecurityStatus(
            isPresent = proto.present,
            engineRunning = proto.engine_running,
            bouncerRunning = proto.bouncer_running,
            engineVersion = proto.engine_version,
            alertsLast24h = proto.alerts_24h,
            localBans = proto.local_bans,
            communityBlocklistIps = proto.community_blocklist_ips,
            packetsDropped = proto.packets_dropped,
            topScenarios = proto.top_scenarios.map {
                HostSecurityStatus.Scenario(name = it.name, count = it.count)
            },
            recentBans = proto.recent_bans.map {
                HostSecurityStatus.Ban(
                    ip = it.ip,
                    country = it.country,
                    scenario = it.scenario,
                    at = it.at,
                )
            },
        )
    }
}
