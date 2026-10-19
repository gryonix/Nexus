package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import gryonixnexusd.v1.Device
import gryonixnexusd.v1.SessionPolicy

class AgentDeviceOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) {
    suspend fun listDevices(): List<Device> = mapping { client.listDevices() }

    suspend fun createTransfer(validMinutes: Int) = mapping { client.createTransfer(validMinutes) }

    suspend fun revoke(deviceID: String): Boolean = mapping { client.revoke(deviceID) }

    suspend fun sessionPolicy(): SessionPolicy = mapping { client.sessionPolicy() }

    suspend fun setSessionPolicy(months: Int): SessionPolicy =
        mapping { client.setSessionPolicy(months) }

    suspend fun pair(code: String, devicePublicKey: String, label: String, deviceUID: String = ""): Device =
        mapping { client.pair(code, devicePublicKey, label, deviceUID) }

    private suspend fun <T> mapping(body: suspend () -> T): T =
        agentFailure("devices") { gate.gated(body) }
}
