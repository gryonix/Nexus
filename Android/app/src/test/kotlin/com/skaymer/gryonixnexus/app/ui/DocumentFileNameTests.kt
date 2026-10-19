package com.skaymer.gryonixnexus.app.ui

import kotlin.test.assertEquals
import org.junit.jupiter.api.Test

/** The name of a picked archive is not a label */
class DocumentFileNameTests {
    @Test
    fun theProvidersNameWins() {
        assertEquals(
            "nextcloud-20260829.tar.gz.gpg",
            DocumentFileName.choose("nextcloud-20260829.tar.gz.gpg", "12345"),
        )
    }

    @Test
    fun withoutOneTheUriIsRead() {
        assertEquals("immich.tar.gz", DocumentFileName.choose(null, "documents/immich.tar.gz"))
        assertEquals("immich.tar.gz", DocumentFileName.choose("  ", "immich.tar.gz"))
    }

    @Test
    fun withNeitherThereIsAFallback() {
        assertEquals("backup.tar.gz", DocumentFileName.choose(null, null))
        assertEquals("backup.tar.gz", DocumentFileName.choose("", ""))
    }
}
