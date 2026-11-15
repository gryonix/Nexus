package com.skaymer.gryonixnexus.app.servers.demo

import gryonixnexusd.v1.SetHostNameRequest
import gryonixnexusd.v1.SetTimeSyncRequest
import gryonixnexusd.v1.SetTimeZoneRequest
import gryonixnexusd.v1.SystemSettings

object DemoSystemSettings {
    private val zones = listOf(
        "Africa/Cairo", "America/New_York", "Asia/Tokyo", "Europe/Berlin",
        "Europe/Kyiv", "Europe/London", "Europe/Moscow", "UTC",
    )
    private val settings = mutableMapOf<String, SystemSettings>()

    @Synchronized
    fun answer(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? {
        var current = settings[machine.id] ?: initial(machine)
        current = when (path) {
            "/gryonixnexusd.v1.Control/GetSystemSettings" -> current
            "/gryonixnexusd.v1.Control/SetTimeZone" ->
                current.copy(time_zone = SetTimeZoneRequest.ADAPTER.decode(request).time_zone)
            "/gryonixnexusd.v1.Control/SetHostName" ->
                current.copy(host_name = SetHostNameRequest.ADAPTER.decode(request).host_name)
            "/gryonixnexusd.v1.Control/SetTimeSync" -> {
                val enabled = SetTimeSyncRequest.ADAPTER.decode(request).enabled
                current.copy(ntp_enabled = enabled, ntp_synchronized = enabled)
            }
            else -> return null
        }
        settings[machine.id] = current
        return current.demoPayload()
    }

    private fun initial(machine: DemoAgentMachine) = SystemSettings(
        time_zone = "Europe/Berlin",
        host_name = machine.deployment.name.lowercase().filter { it.isLetterOrDigit() }.ifEmpty { "orion" },
        ntp_enabled = true,
        ntp_synchronized = true,
        time_zones = zones,
    )
}
