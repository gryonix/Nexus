package com.skaymer.gryonixnexus.app.access

import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** Reading the install report */
class InstallReportParserTests {
    private fun report(name: String): String =
        checkNotNull(javaClass.getResourceAsStream("/$name")) { "missing fixture $name" }
            .bufferedReader().readText()

    private val english = report("install-report-single.txt")
    private val russian = report("install-report-single-ru.txt")

    @Test
    fun `a section is an unindented line and the fields under it`() {
        val titles = InstallReportParser.sections(english).map { it.title }
        assertTrue("Vaultwarden" in titles)
        assertTrue("Nextcloud" in titles)
        assertTrue("AdGuard Home" in titles)
        assertTrue("VPN Panel" in titles)
    }

    @Test
    fun `the address of a section becomes its own field`() {
        val nextcloud = InstallReportParser.sections(english).first { it.title == "Nextcloud" }
        assertEquals(
            InstallReportParser.Field(InstallReportParser.URL, "https://cloud.example.com"),
            nextcloud.fields.first()
        )
    }

    @Test
    fun `the preamble does not become a login`() {
        val titles = ReportedAccount.accounts(InstallReportParser.sections(english)).map { it.title }
        assertEquals(listOf("Vaultwarden", "Nextcloud", "AdGuard Home", "VPN Panel"), titles)
    }

    /** Service status rows are aligned columns, not "label: value" fields */
    @Test
    fun `a block of columns yields no fields`() {
        assertNull(InstallReportParser.sections(english).firstOrNull { it.title == "Service status" })
    }

    @Test
    fun `the generated credentials are read out of their own lines`() {
        val accounts = ReportedAccount.accounts(InstallReportParser.sections(english))
        val nextcloud = accounts.first { it.title == "Nextcloud" }
        assertEquals("admin", nextcloud.login)
        assertEquals("nc-Pw-92kd", nextcloud.password)

        val panel = accounts.first { it.title == "VPN Panel" }
        assertEquals("gryonix", panel.login)
        assertEquals("vp-Pw-33qs", panel.password)
    }

    @Test
    fun `the admin token is read under the label the report prints`() {
        val vaultwarden = ReportedAccount.accounts(InstallReportParser.sections(english))
            .first { it.title == "Vaultwarden" }
        assertEquals("tok-4f2a91c7", vaultwarden.token)
        assertNull(vaultwarden.password)
    }

    @Test
    fun `a report printed in another language yields the same accounts`() {
        val accounts = ReportedAccount.accounts(InstallReportParser.sections(russian))
        assertEquals(
            listOf("Vaultwarden", "Nextcloud", "AdGuard Home", "VPN Panel"),
            accounts.map { it.title }
        )
        assertEquals("admin", accounts.first { it.title == "Nextcloud" }.login)
        assertEquals("nc-Pw-92kd", accounts.first { it.title == "Nextcloud" }.password)
        assertEquals("tok-4f2a91c7", accounts.first { it.title == "Vaultwarden" }.token)
    }

    /** Split on the FIRST separator */
    @Test
    fun `an annotated address keeps its link and loses the note`() {
        val annotated = "Mailcow:      https://mail.example.com  (directory: /opt/mailcow)\n" +
            "  Administrator: admin@example.com\n" +
            "  Password: moohoo\n"
        val account = ReportedAccount.accounts(InstallReportParser.sections(annotated)).single()
        assertEquals("https://mail.example.com", account.website)
        assertEquals("admin@example.com", account.login)
        assertEquals("moohoo", account.password)
    }

    /** Only a section with an http(s) site is a card */
    @Test
    fun `a section without a website is not an account`() {
        val sections = InstallReportParser.sections(english)
        assertTrue(sections.any { it.title.startsWith("Backup passphrase") })
        assertTrue(
            ReportedAccount.accounts(sections).none { it.title.startsWith("Backup passphrase") }
        )
    }

    @Test
    fun `an empty section is dropped`() {
        val sections = InstallReportParser.sections("Nothing here:\n\nSomething: value\n")
        assertEquals(listOf("Something"), sections.map { it.title })
    }

    @Test
    fun `a raw connection string is not cut`() {
        val vpn = InstallReportParser.sections(
            "WireGuard client:\n  Configuration: ss://c2Etbm90LWEtc2l0ZQ==\n"
        ).single()
        assertEquals("ss://c2Etbm90LWEtc2l0ZQ==", vpn.fields.single().value)
        assertTrue(ReportedAccount.accounts(listOf(vpn)).isEmpty())
    }
}
