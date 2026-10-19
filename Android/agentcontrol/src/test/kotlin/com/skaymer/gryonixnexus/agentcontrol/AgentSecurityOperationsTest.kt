package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.servercontrol.HostSecurityStatus
import com.skaymer.gryonixnexus.servercontrol.SshPasswordAccess
import gryonixnexusd.v1.SecurityAllowlist
import gryonixnexusd.v1.SecurityAllowlistEntry
import gryonixnexusd.v1.SecurityBan
import gryonixnexusd.v1.SecurityDecision
import gryonixnexusd.v1.SecurityDecisions
import gryonixnexusd.v1.SetSecurityAllowlistRequest
import gryonixnexusd.v1.SetSecurityDecisionRequest
import gryonixnexusd.v1.SecurityScenario
import gryonixnexusd.v1.SecurityStatus
import gryonixnexusd.v1.SshPasswordState
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentSecurityOperationsTests` */
class AgentSecurityOperationsTest {
    private fun ops(transport: FakeAgentTransport) = AgentSecurityOperations(AgentClient(transport))

    @Test
    fun `the status is mapped field for field`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "/gryonixnexusd.v1.Security/GetSecurityStatus",
            SecurityStatus(
                present = true,
                engine_running = true,
                bouncer_running = true,
                engine_version = "v1.8.0",
                alerts_24h = 49,
                local_bans = 3,
                community_blocklist_ips = 15_737,
                packets_dropped = 21_029,
                top_scenarios = listOf(
                    SecurityScenario(name = "crowdsecurity/ssh-bf", count = 37),
                    SecurityScenario(name = "crowdsecurity/ssh-slow-bf", count = 11),
                ),
                recent_bans = listOf(
                    SecurityBan(
                        ip = "193.233.199.37",
                        country = "RU",
                        scenario = "crowdsecurity/ssh-slow-bf",
                        at = "2026-09-01T16:25:37Z",
                    ),
                ),
            ),
        )

        val status = ops(transport).status()

        assertTrue(status.isPresent)
        assertTrue(status.isHealthy)
        assertEquals("v1.8.0", status.engineVersion)
        assertEquals(49, status.alertsLast24h)
        assertEquals(15_737, status.communityBlocklistIps)
        assertEquals(21_029L, status.packetsDropped)
        assertEquals(
            listOf("crowdsecurity/ssh-bf", "crowdsecurity/ssh-slow-bf"),
            status.topScenarios.map { it.name },
        )
        assertEquals(1, status.recentBans.size)
        assertEquals("RU", status.recentBans.first().country)
        assertEquals("/gryonixnexusd.v1.Security/GetSecurityStatus", transport.paths.single())
    }

    @Test
    fun `a host without CrowdSec maps to not present`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "/gryonixnexusd.v1.Security/GetSecurityStatus",
            SecurityStatus(present = false),
        )

        val status = ops(transport).status()

        assertFalse(status.isPresent)
        assertFalse(status.isHealthy)
        assertTrue(status.recentBans.isEmpty())
    }

    // ── The SSH password switch ─────────────────────────────────────────────

    @Test
    fun `the ssh password state is mapped field for field`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "/gryonixnexusd.v1.Security/GetSshPasswordState",
            SshPasswordState(
                password_login_open = true,
                known = true,
                app_key_present = true,
                drop_in_present = false,
                sshd_present = true,
                login_user = "gryonixnexus",
            ),
        )

        val state = ops(transport).sshPasswordAccess("gryonixnexus", "ssh-ed25519 AAAA x")

        assertTrue(state.isOpen)
        assertFalse(state.isClosed)
        assertTrue(state.canClose)
        assertFalse(state.isOutranked)
        assertEquals("gryonixnexus", state.loginUser)
        assertEquals("/gryonixnexusd.v1.Security/GetSshPasswordState", transport.paths.single())
    }

    /** The guard, as the card sees it */
    @Test
    fun `no proven key means the close is not offered`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "/gryonixnexusd.v1.Security/GetSshPasswordState",
            SshPasswordState(
                password_login_open = true,
                known = true,
                app_key_present = false,
                sshd_present = true,
            ),
        )

        val state = ops(transport).sshPasswordAccess("admin", "ssh-ed25519 AAAA x")

        assertTrue(state.isOpen)
        assertFalse(state.canClose)
    }

    /** "Could not tell" is never rounded to "closed" */
    @Test
    fun `an unknown reading is neither open nor closed`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "/gryonixnexusd.v1.Security/GetSshPasswordState",
            SshPasswordState(known = false, detail = "no systemd-run on this host"),
        )

        val state = ops(transport).sshPasswordAccess("root", "k")

        assertFalse(state.isOpen)
        assertFalse(state.isClosed)
        assertFalse(state.canClose)
        assertEquals("no systemd-run on this host", state.detail)
    }

    @Test
    fun `a drop-in that is outranked is called out`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "/gryonixnexusd.v1.Security/GetSshPasswordState",
            SshPasswordState(
                password_login_open = true,
                known = true,
                drop_in_present = true,
                app_key_present = true,
                sshd_present = true,
            ),
        )

        assertTrue(ops(transport).sshPasswordAccess("root", "k").isOutranked)
    }

    @Test
    fun `a refused close answers with the state the host is actually in`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "/gryonixnexusd.v1.Security/SetSshPasswordLogin",
            SshPasswordState(
                password_login_open = true,
                known = true,
                app_key_present = false,
                sshd_present = true,
                detail = "leaving SSH password login ON: no login key is present for 'admin'",
            ),
        )

        val state = ops(transport).setSshPasswordLogin(false, "admin", "k")

        assertEquals("/gryonixnexusd.v1.Security/SetSshPasswordLogin", transport.paths.single())
        assertTrue(state.isOpen)
        assertTrue(state.detail.contains("no login key"))
    }

    // ─────────────── Bans and the allowlist ───────────────

    @Test
    fun `the decision list is mapped field for field`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "/gryonixnexusd.v1.Security/GetSecurityDecisions",
            SecurityDecisions(
                present = true,
                community_count = 17_707,
                ssh_client_ips = listOf("198.51.100.9", "198.51.100.4"),
                decisions = listOf(
                    SecurityDecision(
                        id = "270036",
                        scope = "Ip",
                        value_ = "198.51.100.9",
                        action = "ban",
                        reason = "crowdsecurity/ssh-slow-bf",
                        country = "DE",
                        as_name = "58243 TELE AG",
                        source = "crowdsec",
                        expires_in = "3h6m42s",
                        events = 11,
                    ),
                ),
            ),
        )

        val lists = ops(transport).decisions()

        assertTrue(lists.isPresent)
        assertEquals(17_707, lists.communityCount)
        assertEquals(listOf("198.51.100.9", "198.51.100.4"), lists.sshClientIps)
        val decision = lists.decisions.single()
        assertEquals("270036", decision.decisionId)
        assertEquals("198.51.100.9", decision.value)
        assertEquals("DE", decision.country)
        assertEquals("58243 TELE AG", decision.asName)
        assertEquals(11, decision.events)
        assertEquals("3h6m42s", decision.expiresIn)
        assertFalse(decision.isManual)
        assertEquals("SSH slow brute force", decision.readableReason)
        assertEquals("/gryonixnexusd.v1.Security/GetSecurityDecisions", transport.paths.single())
    }

    @Test
    fun `a hand-made ban is told apart`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "/gryonixnexusd.v1.Security/GetSecurityDecisions",
            SecurityDecisions(
                present = true,
                decisions = listOf(
                    SecurityDecision(
                        id = "1",
                        value_ = "203.0.113.9",
                        source = "cscli",
                        reason = "gryonixnexus: added by hand",
                    ),
                ),
            ),
        )

        val decision = ops(transport).decisions().decisions.single()

        assertTrue(decision.isManual)
        assertEquals("gryonixnexus: added by hand", decision.readableReason)
    }

    @Test
    fun `lifting carries the id when there is one`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("/gryonixnexusd.v1.Security/SetSecurityDecision", SecurityDecisions(present = true))
        transport.reply("/gryonixnexusd.v1.Security/SetSecurityDecision", SecurityDecisions(present = true))
        val operations = ops(transport)

        operations.setBan(banned = false, value = "198.51.100.9", decisionId = "270036")
        operations.setBan(banned = true, value = "203.0.113.0/24", durationSeconds = 7200, reason = "scanning")

        val lift = SetSecurityDecisionRequest.ADAPTER.decode(transport.calls[0].second)
        assertFalse(lift.banned)
        assertEquals("270036", lift.id)
        assertEquals("198.51.100.9", lift.value_)

        val ban = SetSecurityDecisionRequest.ADAPTER.decode(transport.calls[1].second)
        assertTrue(ban.banned)
        assertTrue(ban.id.isEmpty())
        assertEquals(7200L, ban.duration_seconds)
        assertEquals("scanning", ban.reason)
    }

    @Test
    fun `an allowlist the host cannot keep is reported as unsupported`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "/gryonixnexusd.v1.Security/GetSecurityAllowlist",
            SecurityAllowlist(present = true, supported = false),
        )

        val list = ops(transport).allowlist()

        assertTrue(list.isPresent)
        assertFalse(list.isSupported)
        assertTrue(list.entries.isEmpty())
    }

    @Test
    fun `the allowlist is mapped and asks with the right verb`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "/gryonixnexusd.v1.Security/SetSecurityAllowlist",
            SecurityAllowlist(
                present = true,
                supported = true,
                name = "gryonixnexus",
                ssh_client_ips = listOf("198.51.100.9"),
                entries = listOf(
                    SecurityAllowlistEntry(value_ = "198.51.100.9", comment = "office", expires_in = ""),
                ),
            ),
        )

        val list = ops(transport).setAllowed(allowed = true, value = "198.51.100.9", comment = "office")

        assertEquals("/gryonixnexusd.v1.Security/SetSecurityAllowlist", transport.paths.single())
        val sent = SetSecurityAllowlistRequest.ADAPTER.decode(transport.calls.single().second)
        assertTrue(sent.allowed)
        assertEquals("198.51.100.9", sent.value_)
        // An office address is protected until somebody says otherwise.
        assertEquals(0L, sent.duration_seconds)
        assertTrue(list.allows("198.51.100.9"))
        assertFalse(list.allows("198.51.100.4"))
        assertEquals("office", list.entries.single().comment)
        assertTrue(list.entries.single().expiresIn.isEmpty())
    }

    @Test
    fun `the unknown access claims nothing`() {
        val unknown = SshPasswordAccess.UNKNOWN
        assertFalse(unknown.isOpen)
        assertFalse(unknown.isClosed)
        assertFalse(unknown.canClose)
        assertFalse(unknown.isOutranked)
    }

    @Test
    fun `scenario names are made readable with a safe fallback`() {
        assertEquals(
            "SSH brute force",
            HostSecurityStatus.Scenario("crowdsecurity/ssh-bf", 1).readableName,
        )
        assertEquals(
            "Some New Thing",
            HostSecurityStatus.Scenario("acme/some-new-thing", 1).readableName,
        )
    }
}
