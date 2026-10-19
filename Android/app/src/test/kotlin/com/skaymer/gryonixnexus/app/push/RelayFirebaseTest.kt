package com.skaymer.gryonixnexus.app.push

import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.junit.jupiter.api.Test

class RelayFirebaseTest {
    @Test
    fun `the relay's public settings start Firebase`() {
        val body = """{"fcm":{"project_id":"demo","app_id":"1:42:android:ab","api_key":"AIzaX","sender_id":"42"}}"""
        assertEquals(FirebaseSettings("demo", "1:42:android:ab", "AIzaX", "42"), RelayFirebase.parse(body))
    }

    @Test
    fun `a relay without Android settings says nothing`() {
        assertNull(RelayFirebase.parse("""{"fcm":null}"""))
        assertNull(RelayFirebase.parse("not json"))
    }
}
