package com.skaymer.gryonixnexus.aiassistant

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class RedactorTest {
    private fun gone(input: String, secret: String) {
        val out = Redactor.redact(input)
        assertFalse(out.contains(secret), out)
        assertTrue(out.contains("[REDACTED"), out)
    }

    @Test fun passwordAssignments() {
        gone("password=hunter2xyz", "hunter2xyz")
        gone("DB_PASSWORD: s3cr3t!", "s3cr3t!")
        gone("{\"password\": \"correct horse\"}", "correct horse")
        gone("passwd = 'abc 123'", "abc 123")
    }

    @Test fun keyValueNames() {
        gone("API_KEY=abcd1234", "abcd1234")
        gone("export SECRET_TOKEN=zzz999", "zzz999")
        gone("client-secret: top", "top")
        gone("key=value1", "value1")
        gone("SSH_KEY=material", "material")
    }

    @Test fun keepsInnocentWords() {
        assertEquals("monkey=3 and keyboard=on", Redactor.redact("monkey=3 and keyboard=on"))
        assertEquals("authorization failed for user", Redactor.redact("authorization failed for user"))
        assertEquals("PATH=/usr/bin:/bin", Redactor.redact("PATH=/usr/bin:/bin"))
    }

    @Test fun authorizationHeaders() {
        gone("Authorization: Bearer abc.def.ghi", "abc.def.ghi")
        gone("authorization: Basic dXNlcjpwYXNz", "dXNlcjpwYXNz")
        gone("curl -H 'Authorization: token ghp_abc'", "ghp_abc")
        gone("Proxy-Authorization: Basic cXdlcg==", "cXdlcg==")
    }

    @Test fun bareBearer() = gone("sent Bearer 1234567890abcdef today", "1234567890abcdef")

    @Test fun jwt() {
        val jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.c2lnbmF0dXJl"
        gone("session $jwt ok", jwt)
    }

    @Test fun privateKeyBlock() {
        val block = "-----BEGIN OPENSSH PRIVATE KEY-----\nAAAAB3Nz\nline2\n-----END OPENSSH PRIVATE KEY-----"
        assertEquals("before\n[REDACTED PRIVATE KEY]\nafter", Redactor.redact("before\n$block\nafter"))
    }

    @Test fun unterminatedPrivateKey() {
        assertFalse(Redactor.redact("x\n-----BEGIN RSA PRIVATE KEY-----\nMIIE").contains("MIIE"))
    }

    @Test fun longHexAndBase64() {
        val hex = "ab12".repeat(8)
        gone("id $hex up", hex)
        val b64 = "Zm9vYmFyMTIzNDU2Nzg5MGFiY2RlZmdoaWprbG1ub3A="
        gone("blob $b64", b64)
    }

    @Test fun shortTokensAndPlainLongWordsStay() {
        assertEquals("abcdef0123456789", Redactor.redact("abcdef0123456789"))
        val word = "a".repeat(40)
        assertEquals(word, Redactor.redact(word))
    }

    @Test fun urlCredentials() = gone("postgres://admin:pw123@db:5432/x", "pw123")

    @Test fun commandLineFlags() {
        gone("mysql --password hunter22 -h db", "hunter22")
        gone("tool --token=abc12345", "abc12345")
    }

    @Test fun idempotent() {
        val once = Redactor.redact("password=abc token: xyz Authorization: Bearer q1w2e3r4")
        assertEquals(once, Redactor.redact(once))
    }

    @Test fun multilineKeepsOtherLines() {
        assertEquals("line one\nTOKEN=[REDACTED]\nline three", Redactor.redact("line one\nTOKEN=abc\nline three"))
    }
}
