package com.skaymer.gryonixnexus.app.notify

import gryonixnexusd.v1.NotifyChannel
import gryonixnexusd.v1.NotifySettings
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.junit.jupiter.api.Test

class NotifySyncTest {
    private val key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMjhZbMLa1yPZt87ATUHLO4OUNZoQu6+22Re+KW7HKUl phone"

    private fun server(custom: Boolean, wishes: NotifyPreferences) = NotifySettings(
        channel = NotifyChannel.NOTIFY_CHANNEL_RELAY,
        checks = wishes.checks,
        language = "ru",
        custom_checks = custom,
        quiet_keys = listOf("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMjhZbMLa1yPZt87ATUHLO4OUNZoQu6+22Re+KW7HKUl"),
    )

    @Test
    fun `a server following the defaults gets them`() {
        val wanted = NotifyPreferences(sshLogins = false)
        val request = NotifyViewModel.syncRequest(server(false, NotifyPreferences()), wanted, "ru", key)
        assertEquals(false, request?.checks?.ssh_logins)
        assertEquals(false, request?.custom_checks)
    }

    @Test
    fun `a server with its own choice keeps it`() {
        val current = server(true, NotifyPreferences(backups = false))
        assertNull(NotifyViewModel.syncRequest(current, NotifyPreferences(sshLogins = false), "ru", key))
    }

    @Test
    fun `an unknown app key is sent`() {
        val current = server(true, NotifyPreferences())
        val request = NotifyViewModel.syncRequest(current, NotifyPreferences(), "ru", "ssh-ed25519 AAAAother tablet")
        assertEquals("ssh-ed25519 AAAAother tablet", request?.app_public_key)
        assertEquals(true, request?.custom_checks)
    }

    @Test
    fun `a server's checks read back as wishes`() {
        val wishes = NotifyPreferences(disks = false, operations = true, sshLogins = false)
        assertEquals(wishes.copy(appUpdate = true), NotifyPreferences.from(wishes.checks))
    }

    @Test
    fun `a silent second machine takes the main one's channel`() {
        val primary = server(false, NotifyPreferences()).copy(relay_url = "https://push.example.com")
        val request = NotifyViewModel.mirrorRequest(primary, NotifySettings(), key)
        assertEquals(NotifyChannel.NOTIFY_CHANNEL_RELAY, request?.channel)
        assertEquals("https://push.example.com", request?.relay_url)
        assertEquals(primary.checks, request?.checks)
        assertEquals("ru", request?.language)
    }

    @Test
    fun `a matching second machine is left alone`() {
        val primary = server(false, NotifyPreferences()).copy(relay_url = "https://push.example.com")
        assertNull(NotifyViewModel.mirrorRequest(primary, primary, key))
    }

    @Test
    fun `a following server gets the app's channel once`() {
        val current = server(false, NotifyPreferences()).copy(relay_url = "https://push.gryonix.com")
        val ntfy = NotifyChannelDefault(channel = NotifyChannel.NOTIFY_CHANNEL_NTFY, ntfyTopic = "gnx-topic")
        val request = NotifyViewModel.syncRequest(current, NotifyPreferences(), "ru", key, ntfy)
        assertEquals(NotifyChannel.NOTIFY_CHANNEL_NTFY, request?.channel)
        assertEquals("gnx-topic", request?.ntfy_topic)
        val relay = NotifyChannelDefault(relayUrl = "https://push.gryonix.com")
        assertNull(NotifyViewModel.syncRequest(current, NotifyPreferences(), "ru", key, relay), "already in step")
    }

    @Test
    fun `a server keeping its channel is left alone`() {
        val current = server(false, NotifyPreferences()).copy(channel = NotifyChannel.NOTIFY_CHANNEL_NTFY, ntfy_topic = "mine")
        assertNull(NotifyViewModel.syncRequest(current, NotifyPreferences(), "ru", key, null))
    }

    @Test
    fun `only a server with its own setup keeps it at first sight`() {
        val store = com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore()
        val choice = NotifyChannelDefault()
        val ours = server(false, NotifyPreferences()).copy(relay_url = "https://push.gryonix.com:8444")
        kotlin.test.assertFalse(NotifyChannelDefault.keepsOwn(ours, "a", choice, store))
        kotlin.test.assertFalse(NotifyChannelDefault.keepsOwn(ours.copy(channel = NotifyChannel.NOTIFY_CHANNEL_OFF), "b", choice, store))
        val own = ours.copy(channel = NotifyChannel.NOTIFY_CHANNEL_NTFY)
        kotlin.test.assertTrue(NotifyChannelDefault.keepsOwn(own, "c", choice, store))
        kotlin.test.assertTrue(NotifyChannelDefault.keepsOwn(ours, "c", choice, store), "decided once, then remembered")
    }

    @Test
    fun `the app's channel is kept across launches`() {
        val store = com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore()
        val first = NotifyChannelDefault.load(store)
        assertEquals(NotifyChannel.NOTIFY_CHANNEL_RELAY, first.channel)
        assertEquals(first.ntfyTopic, NotifyChannelDefault.load(store).ntfyTopic, "one topic, made once")
        first.copy(channel = NotifyChannel.NOTIFY_CHANNEL_NTFY).save(store)
        assertEquals(NotifyChannel.NOTIFY_CHANNEL_NTFY, NotifyChannelDefault.load(store).channel)
    }
}
