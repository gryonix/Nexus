package com.skaymer.gryonixnexus.app.notify

import gryonixnexusd.v1.NotifyChannel
import gryonixnexusd.v1.NotifyChecks
import gryonixnexusd.v1.SetNotifySettingsRequest
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class NotifyTransferTest {
    private val request = SetNotifySettingsRequest(
        channel = NotifyChannel.NOTIFY_CHANNEL_NTFY,
        ntfy_url = "https://ntfy.example.net",
        ntfy_topic = "gnx-abc",
        custom_checks = true,
        language = "de",
        checks = NotifyChecks(raid = true, services = false, disk_space_percent = 80, ssh_logins = true),
    )

    @Test
    fun `a file carries the channel and the checks and comes back the same`() {
        val read = NotifyTransfer.decode(NotifyTransfer.of(request).encoded())
        val applied = read.applied(SetNotifySettingsRequest(language = "uk"))
        assertEquals(NotifyChannel.NOTIFY_CHANNEL_NTFY, applied.channel)
        assertEquals("gnx-abc", applied.ntfy_topic)
        assertEquals("https://ntfy.example.net", applied.ntfy_url)
        assertTrue(applied.custom_checks)
        assertFalse(applied.checks!!.services)
        assertEquals(80, applied.checks!!.disk_space_percent)
        assertEquals("uk", applied.language)
    }

    @Test
    fun `a server that follows the defaults keeps its own checks`() {
        val read = NotifyTransfer.decode(NotifyTransfer.of(request.copy(custom_checks = false)).encoded())
        val draft = SetNotifySettingsRequest(checks = NotifyChecks(services = true))
        val applied = read.applied(draft)
        assertFalse(applied.custom_checks)
        assertTrue(applied.checks!!.services)
    }

    @Test
    fun `other files are refused`() {
        assertEquals(
            NotifyTransfer.Failure.NOT_A_PUSH_FILE,
            assertFailsWith<NotifyTransfer.Refused> { NotifyTransfer.decode("{}") }.reason,
        )
        assertEquals(
            NotifyTransfer.Failure.NOT_A_PUSH_FILE,
            assertFailsWith<NotifyTransfer.Refused> { NotifyTransfer.decode("not json") }.reason,
        )
        val future = NotifyTransfer.of(request).copy(version = 99).encoded()
        assertEquals(
            NotifyTransfer.Failure.NEWER_VERSION,
            assertFailsWith<NotifyTransfer.Refused> { NotifyTransfer.decode(future) }.reason,
        )
    }
}
