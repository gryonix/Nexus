package com.skaymer.gryonixnexus.app.notify

import com.skaymer.gryonixnexus.app.shell.SettingsStore
import gryonixnexusd.v1.NotifyChannel
import gryonixnexusd.v1.NotifySettings
import gryonixnexusd.v1.SetNotifySettingsRequest
import java.net.URI

/** Where every server sends alerts, unless it keeps its own */
data class NotifyChannelDefault(
    val channel: NotifyChannel = NotifyChannel.NOTIFY_CHANNEL_RELAY,
    val relayUrl: String = NotifyViewModel.DEFAULT_RELAY_URL,
    val ntfyUrl: String = "https://ntfy.sh",
    val ntfyTopic: String = "",
) {
    /** A fingerprint to tell whether a server is in step */
    val fingerprint: String get() = listOf(name(channel), relayUrl, ntfyUrl, ntfyTopic).joinToString("|")

    /** Whether a server already sends this way */
    fun matches(settings: NotifySettings): Boolean = when (channel) {
        NotifyChannel.NOTIFY_CHANNEL_RELAY ->
            settings.channel == NotifyChannel.NOTIFY_CHANNEL_RELAY && settings.relay_url == relayUrl
        NotifyChannel.NOTIFY_CHANNEL_NTFY -> settings.channel == NotifyChannel.NOTIFY_CHANNEL_NTFY &&
            settings.ntfy_url == ntfyUrl && settings.ntfy_topic == ntfyTopic
        else -> settings.channel == NotifyChannel.NOTIFY_CHANNEL_OFF ||
            settings.channel == NotifyChannel.NOTIFY_CHANNEL_UNSPECIFIED
    }

    /** The request, sending this way */
    fun applied(request: SetNotifySettingsRequest): SetNotifySettingsRequest = request.copy(
        channel = if (channel == NotifyChannel.NOTIFY_CHANNEL_UNSPECIFIED) NotifyChannel.NOTIFY_CHANNEL_OFF else channel,
        relay_url = relayUrl,
        ntfy_url = ntfyUrl,
        ntfy_topic = ntfyTopic,
    )

    fun save(store: SettingsStore) {
        store.setString(CHANNEL, name(channel))
        store.setString(RELAY_URL, relayUrl.trim())
        store.setString(NTFY_URL, ntfyUrl.trim())
        store.setString(NTFY_TOPIC, ntfyTopic.trim())
    }

    companion object {
        const val CHANNEL = "notify.channel"
        const val RELAY_URL = "notify.relayURL"
        const val NTFY_URL = "notify.ntfyURL"
        const val NTFY_TOPIC = "notify.ntfyTopic"

        fun load(store: SettingsStore): NotifyChannelDefault {
            val topic = store.string(NTFY_TOPIC)?.trim()?.ifEmpty { null }
                ?: NotifyViewModel.randomTopic().also { store.setString(NTFY_TOPIC, it) }
            return NotifyChannelDefault(
                channel = channel(store.string(CHANNEL)),
                relayUrl = store.string(RELAY_URL)?.trim()?.ifEmpty { null } ?: NotifyViewModel.DEFAULT_RELAY_URL,
                ntfyUrl = store.string(NTFY_URL)?.trim()?.ifEmpty { null } ?: "https://ntfy.sh",
                ntfyTopic = topic,
            )
        }

        fun ownKey(deploymentID: String) = "notify.ownChannel.$deploymentID"

        /** Whether a server keeps its own channel, decided once */
        fun keepsOwn(settings: NotifySettings, deploymentID: String, wanted: NotifyChannelDefault, store: SettingsStore): Boolean {
            store.boolean(ownKey(deploymentID))?.let { return it }
            val own = !(settings.channel == NotifyChannel.NOTIFY_CHANNEL_OFF ||
                settings.channel == NotifyChannel.NOTIFY_CHANNEL_UNSPECIFIED ||
                wanted.matches(settings) || isOurRelay(settings))
            store.setBoolean(ownKey(deploymentID), own)
            return own
        }

        /** The public relay, on any port */
        fun isOurRelay(settings: NotifySettings): Boolean =
            settings.channel == NotifyChannel.NOTIFY_CHANNEL_RELAY &&
                host(settings.relay_url) == host(NotifyViewModel.DEFAULT_RELAY_URL)

        private fun host(url: String): String? = runCatching { URI(url).host }.getOrNull()

        private fun channel(name: String?): NotifyChannel = when (name) {
            "ntfy" -> NotifyChannel.NOTIFY_CHANNEL_NTFY
            "off" -> NotifyChannel.NOTIFY_CHANNEL_OFF
            else -> NotifyChannel.NOTIFY_CHANNEL_RELAY
        }

        private fun name(channel: NotifyChannel): String = when (channel) {
            NotifyChannel.NOTIFY_CHANNEL_NTFY -> "ntfy"
            NotifyChannel.NOTIFY_CHANNEL_RELAY -> "relay"
            else -> "off"
        }
    }
}
