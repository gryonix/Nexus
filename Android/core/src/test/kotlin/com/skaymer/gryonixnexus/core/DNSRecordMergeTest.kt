package com.skaymer.gryonixnexus.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class DNSRecordMergeTest {
    private fun txt(name: String, value: String) = DNSRecord(name, DNSRecord.RecordType.TXT, value)

    @Test
    fun anExistingSPFIsJoinedNotReplaced() {
        val ours = txt("example.com", "v=spf1 mx -all")
        val merged = ours.merged("\"v=spf1 include:_spf.google.com ~all\"")
        assertEquals("v=spf1 include:_spf.google.com mx ~all", merged.value)
        assertEquals("v=spf1 mx -all", ours.merged("v=DMARC1; p=none").value)
    }

    @Test
    fun aSetKeepsTheOwnersOtherTextAndTakesNoSecondSPF() {
        val ours = txt("example.com", "v=spf1 mx -all")
        val existing = listOf("\"google-site-verification=abc\"", "\"v=spf1 include:mailgun.org -all\"")
        val updated = ours.updatedSet(existing) { bindTXTRData(it.value) }
        assertEquals(
            listOf("\"google-site-verification=abc\"", "\"v=spf1 include:mailgun.org mx -all\""),
            updated,
        )
        val dmarc = txt("_dmarc.example.com", "v=DMARC1; p=quarantine")
        assertNull(dmarc.updatedSet(listOf("\"v=DMARC1; p=reject\"")) { bindTXTRData(it.value) })
    }

    @Test
    fun anAddressIsAddedToItsSetOnlyWhenAbsent() {
        val record = DNSRecord("mail.example.com", DNSRecord.RecordType.A, "203.0.113.9")
        assertEquals(listOf("198.51.100.1", "203.0.113.9"), record.updatedSet(listOf("198.51.100.1")) { it.value })
        assertNull(record.updatedSet(listOf("203.0.113.9", "198.51.100.1")) { it.value })
    }
}
