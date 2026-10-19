package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import gryonixnexusd.v1.PutVaultEntriesRequest
import gryonixnexusd.v1.VaultEntry
import gryonixnexusd.v1.VaultSnapshot
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentVaultOperationsTests` and `VaultMergeTests` */
class AgentVaultOperationsTest {
    private fun entry(
        id: String,
        password: String = "hunter2",
        at: Long = 0,
        by: String = "",
        deleted: Boolean = false,
    ) = VaultEntry(
        id = id,
        host = "single",
        title = "Vaultwarden",
        password = password,
        updated_at = at,
        updated_by = by,
        deleted = deleted,
    )

    private fun sent(transport: FakeAgentTransport): List<VaultEntry> =
        PutVaultEntriesRequest.ADAPTER
            .decode(transport.calls.first { it.first.endsWith("PutVaultEntries") }.second)
            .entries

    // -------------------------------------------------------- What is sent

    @Test
    fun `a zero timestamp is sent as zero`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("PutVaultEntries", VaultSnapshot())
        AgentVaultOperations(AgentClient(transport), deviceUID = "phone-a")
            .save(listOf(entry("single|Vaultwarden", at = 0, by = "agent")))
        assertEquals(0L, sent(transport).first().updated_at)
    }

    @Test
    fun `an edit keeps the callers time`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("PutVaultEntries", VaultSnapshot())
        AgentVaultOperations(AgentClient(transport), deviceUID = "phone-a")
            .save(listOf(entry("id", at = 1_700_000_000, by = "phone-a")))
        assertEquals(1_700_000_000L, sent(transport).first().updated_at)
    }

    @Test
    fun `an empty writer is filled in with this device`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("PutVaultEntries", VaultSnapshot())
        AgentVaultOperations(AgentClient(transport), deviceUID = "phone-a")
            .save(listOf(entry("id", at = 100, by = "")))
        assertEquals("phone-a", sent(transport).first().updated_by)
    }

    @Test
    fun `a named writer is left alone`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("PutVaultEntries", VaultSnapshot())
        AgentVaultOperations(AgentClient(transport), deviceUID = "phone-a")
            .save(listOf(entry("id", at = 0, by = "agent")))
        assertEquals("agent", sent(transport).first().updated_by)
    }

    @Test
    fun `tombstones are not offered as entries`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "GetVault",
            VaultSnapshot(entries = listOf(entry("kept", at = 100), entry("gone", at = 100, deleted = true))),
        )
        val entries = AgentVaultOperations(AgentClient(transport)).entries()
        assertEquals(listOf("kept"), entries.map { it.id })
    }

    // ------------------------------------------------------------- Merging

    @Test
    fun `the newer edit wins whichever side it is on`() {
        val mine = entry("id", password = "newer", at = 200, by = "phone-a")
        val theirs = entry("id", password = "older", at = 100, by = "phone-b")
        assertEquals("newer", VaultMerge.merged(listOf(mine), listOf(theirs)).single().password)
        assertEquals("newer", VaultMerge.merged(listOf(theirs), listOf(mine)).single().password)
    }

    /** The tie-break is the device id */
    @Test
    fun `an equal timestamp is broken by the device id, not by side`() {
        val a = entry("id", password = "from-a", at = 100, by = "phone-a")
        val b = entry("id", password = "from-b", at = 100, by = "phone-b")
        assertEquals("from-b", VaultMerge.merged(listOf(a), listOf(b)).single().password)
        assertEquals("from-b", VaultMerge.merged(listOf(b), listOf(a)).single().password)
    }

    /** A tombstone beats an older edit… */
    @Test
    fun `a tombstone beats an older edit`() {
        val gone = entry("id", password = "", at = 200, by = "phone-b", deleted = true)
        val old = entry("id", password = "still-here", at = 100, by = "phone-a")
        assertTrue(VaultMerge.merged(listOf(old), listOf(gone)).isEmpty())
    }

    @Test
    fun `a newer edit revives a deleted id`() {
        val gone = entry("id", password = "", at = 100, by = "phone-b", deleted = true)
        val fresh = entry("id", password = "recorded-again", at = 200, by = "phone-a")
        assertEquals("recorded-again", VaultMerge.merged(listOf(fresh), listOf(gone)).single().password)
    }

    @Test
    fun `resolved keeps the tombstone that merged drops`() {
        val gone = entry("id", password = "", at = 200, by = "phone-b", deleted = true)
        val old = entry("id", password = "still-here", at = 100, by = "phone-a")
        assertTrue(VaultMerge.merged(listOf(old), listOf(gone)).isEmpty())
        assertEquals(true, VaultMerge.resolved(listOf(old), listOf(gone)).single().deleted)
    }

    @Test
    fun `only what is newer or unknown is pushed`() {
        val mineNewer = entry("newer", at = 200, by = "phone-a")
        val mineOlder = entry("older", at = 100, by = "phone-a")
        val mineNew = entry("unknown-to-the-server", at = 100, by = "phone-a")
        val remote = listOf(
            entry("newer", at = 100, by = "phone-b"),
            entry("older", at = 200, by = "phone-b"),
        )
        assertEquals(
            listOf("newer", "unknown-to-the-server"),
            VaultMerge.toPush(listOf(mineNewer, mineOlder, mineNew), remote).map { it.id },
        )
    }

    @Test
    fun `an entry without an id is dropped rather than merged`() {
        assertTrue(VaultMerge.merged(listOf(entry("")), emptyList()).isEmpty())
        assertTrue(VaultMerge.toPush(listOf(entry("")), emptyList()).isEmpty())
    }
}
