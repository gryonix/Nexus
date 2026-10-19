package com.skaymer.gryonixnexus.core

import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import org.junit.jupiter.api.Test

class StringTemplateRendererTest {
    private val renderer = StringTemplateRenderer()

    @Test
    fun `every placeholder is replaced by its value`() {
        assertEquals(
            "server mail.example.com port 587",
            renderer.render("server {{host}} port {{port}}", mapOf("host" to "mail.example.com", "port" to "587")),
        )
    }

    @Test
    fun `a template with no placeholders comes back unchanged`() {
        assertEquals("plain text", renderer.render("plain text", emptyMap()))
    }

    @Test
    fun `an unsubstituted placeholder is refused rather than shipped`() {
        val error = assertFailsWith<UnresolvedPlaceholderException> {
            renderer.render("host {{host}} port {{port}}", mapOf("host" to "mail.example.com"))
        }
        assertEquals("{{port}}", error.placeholder)
    }

    @Test
    fun `braces inside a substituted value are data not a placeholder`() {
        assertEquals(
            "pw={{ not a key }}",
            renderer.render("pw={{secret}}", mapOf("secret" to "{{ not a key }}")),
        )
    }

    @Test
    fun `a value supplied for a key the template never mentions is ignored`() {
        assertEquals("only host", renderer.render("only host", mapOf("unused" to "x")))
    }
}
