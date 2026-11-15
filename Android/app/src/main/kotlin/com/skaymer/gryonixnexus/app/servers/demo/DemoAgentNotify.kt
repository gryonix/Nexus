package com.skaymer.gryonixnexus.app.servers.demo

import gryonixnexusd.v1.NotifyChannel
import gryonixnexusd.v1.NotifySettings
import gryonixnexusd.v1.NotifyTestResult
import gryonixnexusd.v1.RegisterNotifyDeviceRequest
import gryonixnexusd.v1.SetNotifySettingsRequest

/** The server's alerts: channel, checks and devices */
object DemoAgentNotify {
    private const val PREFIX = "/gryonixnexusd.v1.Notify/"

    fun answer(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? {
        if (!path.startsWith(PREFIX)) return null
        return when (path.removePrefix(PREFIX)) {
            "GetNotifySettings" -> settings(machine).demoPayload()
            "SetNotifySettings" -> {
                val asked = SetNotifySettingsRequest.ADAPTER.decode(request)
                change(machine) {
                    it.copy(
                        channel = asked.channel, relay_url = asked.relay_url, ntfy_url = asked.ntfy_url,
                        ntfy_topic = asked.ntfy_topic, checks = asked.checks, language = asked.language,
                        custom_checks = asked.custom_checks,
                    )
                }.demoPayload()
            }
            "RegisterNotifyDevice" -> {
                RegisterNotifyDeviceRequest.ADAPTER.decode(request)
                change(machine) { it.copy(devices = it.devices + 1) }.demoPayload()
            }
            "UnregisterNotifyDevice" -> change(machine) { it.copy(devices = maxOf(0, it.devices - 1)) }.demoPayload()
            else -> NotifyTestResult(ok = true).demoPayload()
        }
    }

    private fun settings(machine: DemoAgentMachine): NotifySettings = DemoAgentState.memory(machine) {
        it.notify ?: NotifySettings(
            channel = NotifyChannel.NOTIFY_CHANNEL_OFF,
            server_id = machine.id,
            last_check_at = System.currentTimeMillis() / 1000,
        ).also { fresh -> it.notify = fresh }
    }

    private fun change(machine: DemoAgentMachine, edit: (NotifySettings) -> NotifySettings): NotifySettings {
        val next = edit(settings(machine))
        DemoAgentState.memory(machine) { it.notify = next }
        return next
    }
}
