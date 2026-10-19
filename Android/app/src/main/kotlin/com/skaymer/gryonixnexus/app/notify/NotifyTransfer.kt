package com.skaymer.gryonixnexus.app.notify

import gryonixnexusd.v1.NotifyChannel
import gryonixnexusd.v1.NotifyChecks
import gryonixnexusd.v1.SetNotifySettingsRequest
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** A server's gryonixPush settings as a small file */
@Serializable
data class NotifyTransfer(
    val type: String = TYPE,
    val version: Int = VERSION,
    val channel: String,
    val relayURL: String,
    val ntfyURL: String,
    val ntfyTopic: String,
    val customChecks: Boolean,
    val checks: Checks,
) {
    @Serializable
    data class Checks(
        val raid: Boolean = true,
        val smart: Boolean = true,
        val diskSpace: Boolean = true,
        val diskSpacePercent: Int = 90,
        val services: Boolean = true,
        val backups: Boolean = true,
        val agentUpdate: Boolean = true,
        val operations: Boolean = false,
        val sshLogins: Boolean = true,
    )

    enum class Failure { NOT_A_PUSH_FILE, NEWER_VERSION }

    class Refused(val reason: Failure) : Exception(reason.name)

    fun encoded(): String = json.encodeToString(serializer(), this)

    fun applied(draft: SetNotifySettingsRequest): SetNotifySettingsRequest {
        val wire = NotifyChecks(
            raid = checks.raid, smart = checks.smart, disk_space = checks.diskSpace,
            disk_space_percent = checks.diskSpacePercent.coerceIn(50, 99),
            services = checks.services, backups = checks.backups, agent_update = checks.agentUpdate,
            operations = checks.operations, ssh_logins = checks.sshLogins,
        )
        return draft.copy(
            channel = channelOf(channel), relay_url = relayURL, ntfy_url = ntfyURL, ntfy_topic = ntfyTopic,
            custom_checks = customChecks, checks = if (customChecks) wire else draft.checks,
        )
    }

    companion object {
        const val TYPE = "gryonixpush"
        const val VERSION = 1

        private val json = Json { prettyPrint = true; ignoreUnknownKeys = true; encodeDefaults = true }

        fun of(request: SetNotifySettingsRequest): NotifyTransfer {
            val checks = request.checks ?: NotifyChecks()
            return NotifyTransfer(
                channel = nameOf(request.channel), relayURL = request.relay_url, ntfyURL = request.ntfy_url,
                ntfyTopic = request.ntfy_topic, customChecks = request.custom_checks,
                checks = Checks(
                    raid = checks.raid, smart = checks.smart, diskSpace = checks.disk_space,
                    diskSpacePercent = checks.disk_space_percent, services = checks.services,
                    backups = checks.backups, agentUpdate = checks.agent_update,
                    operations = checks.operations, sshLogins = checks.ssh_logins,
                ),
            )
        }

        fun decode(text: String): NotifyTransfer {
            val file = runCatching { json.decodeFromString(serializer(), text) }.getOrNull()
            if (file == null || file.type != TYPE || file.channel !in CHANNELS) throw Refused(Failure.NOT_A_PUSH_FILE)
            if (file.version > VERSION) throw Refused(Failure.NEWER_VERSION)
            return file
        }

        private val CHANNELS = setOf("off", "relay", "ntfy")

        private fun nameOf(channel: NotifyChannel) = when (channel) {
            NotifyChannel.NOTIFY_CHANNEL_RELAY -> "relay"
            NotifyChannel.NOTIFY_CHANNEL_NTFY -> "ntfy"
            else -> "off"
        }

        private fun channelOf(name: String) = when (name) {
            "relay" -> NotifyChannel.NOTIFY_CHANNEL_RELAY
            "ntfy" -> NotifyChannel.NOTIFY_CHANNEL_NTFY
            else -> NotifyChannel.NOTIFY_CHANNEL_OFF
        }
    }
}
