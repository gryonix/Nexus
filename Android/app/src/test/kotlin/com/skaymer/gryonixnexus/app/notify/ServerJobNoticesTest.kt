package com.skaymer.gryonixnexus.app.notify

import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ServerJobNoticesTest {
    private fun card(json: String) = ServerJobCard.from(Json.parseToJsonElement(json).jsonObject)

    @Test
    fun aStartNamesTheJobAndAStepShowsItsCounter() {
        val start = card("""{"job":"6ac-1","kind":"update","title":"Updating Immich","server":"orion","state":{"progressText":"Starting…","isFinished":false}}""")
        assertEquals("Updating Immich", start?.title)
        assertEquals("update", start?.kind)
        val step = card("""{"job":"6ac-1","state":{"progressText":"Pulling","progress":0.4,"step":3,"steps":7}}""")
        assertEquals("3/7 · Pulling", step?.line)
        assertEquals(0.4, step?.progress)
        assertNull(step?.title)
    }

    @Test
    fun theEndAndAFailureAreRead() {
        val failed = card("""{"job":"j","state":{"progressText":"x","isFinished":true,"errorMessage":"disk full"}}""")
        assertTrue(failed!!.finished)
        assertEquals("disk full", failed.error)
        assertTrue(card("""{"job":"j","end":true,"state":{}}""")!!.end)
        assertNull(card("""{"state":{}}"""))
    }

    @Test
    fun aJobIsRememberedFromItsStartUntilItsEnd() {
        val store = InMemorySettingsStore()
        ServerJobNotices.store = store
        ServerJobNotices.received("srv", card("""{"job":"j1","kind":"backup","title":"Backup","server":"orion","state":{}}""")!!)
        assertNotNull(store.string("serverJob.j1"))
        ServerJobNotices.received("srv", card("""{"job":"j1","state":{"progressText":"Copying"}}""")!!)
        ServerJobNotices.received("srv", card("""{"job":"j1","end":true,"state":{"isFinished":true}}""")!!)
        assertNull(store.string("serverJob.j1"))
        ServerJobNotices.received("srv", card("""{"job":"j2","state":{"progressText":"orphan"}}""")!!)
        assertNull(store.string("serverJob.j2"), "a step without a start shows nothing")
    }
}
