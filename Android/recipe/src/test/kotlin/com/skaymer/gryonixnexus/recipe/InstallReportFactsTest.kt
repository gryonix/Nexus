package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class InstallReportFactsTest {
    private fun report(language: AppLanguage, domain: String): String = """
        ${L10nScripts.reportTitle(language)}
        ${L10nScripts.domainLabel(language)} $domain
        ${L10nScripts.mailHostLabel(language)} mail.$domain
    """.trimIndent()

    @Test
    fun `the domain is read in every language the report can be written in`() {
        for (language in AppLanguage.entries) {
            assertEquals("example.net", InstallReportFacts.domain(report(language, "example.net")),
                         "the report is generated in the owner's language: $language")
        }
    }

    @Test
    fun `a subdomain deployment reads back whole`() {
        assertEquals("b.example.net",
                     InstallReportFacts.domain(report(AppLanguage.EN, "b.example.net")))
    }

    @Test
    fun `a report without the line answers nothing`() {
        assertNull(InstallReportFacts.domain(""))
        assertNull(InstallReportFacts.domain("Service status:\n  docker active\n"))
    }

    @Test
    fun `prose after the label is not taken for a domain`() {
        for (value in listOf("not set", "example .com", "https://example.net", "example.net:443",
                             ".example.net", "example.net.", "no-dot")) {
            assertNull(InstallReportFacts.domain("Domain: $value"), "\"$value\" is not a domain")
        }
    }

    @Test
    fun `the column padding is not part of the value`() {
        assertEquals("example.net", InstallReportFacts.domain("Domain:         example.net   "))
    }

    @Test
    fun `the answer is lowercased like every other hostname here`() {
        assertEquals("example.net", InstallReportFacts.domain("Domain: example.net"))
    }
}
