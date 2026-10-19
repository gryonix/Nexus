package com.skaymer.gryonixnexus.app.servers

import android.icu.text.MeasureFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.core.WakeOnLAN
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Locale
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Silence a card waits before offering a wake-up */
object WakeButtonSettings {
    const val KEY = "wake.buttonDelay"
    const val DEFAULT = 15
    val DELAYS = listOf(15, 30, 60, 120, 300, 600)

    fun delay(store: SettingsStore): Int = store.string(KEY)?.toIntOrNull()?.takeIf { it in DELAYS } ?: DEFAULT

    fun title(seconds: Int, locale: Locale = Locale.getDefault()): String {
        val format = MeasureFormat.getInstance(locale, MeasureFormat.FormatWidth.WIDE)
        return if (seconds < 60) format.format(Measure(seconds, MeasureUnit.SECOND))
        else format.format(Measure(seconds / 60, MeasureUnit.MINUTE))
    }
}

/** Whether this device can reach a machine's local network */
object LocalNetworkCheck {
    /** null when neither the machine's address nor network is known */
    suspend fun isOnNetwork(node: DeploymentNode, broadcast: String?): Boolean? = withContext(Dispatchers.IO) {
        val host = node.endpoint.host
        val machine = if (WakeOnLAN.broadcastAddress(host) != null) host
        else if (WakeOnLAN.isLocalNetwork(host)) resolveBriefly(host)
        else null
        WakeOnLAN.sharesNetwork(deviceAddresses(), machine, broadcast)
    }

    /** A name's address, or null after two seconds */
    private fun resolveBriefly(host: String): String? = runCatching {
        CompletableFuture.supplyAsync { WakeOnLAN.resolveIPv4(host) }.get(2, TimeUnit.SECONDS)
    }.getOrNull()

    /** Every IPv4 address this device holds, with its prefix */
    fun deviceAddresses(): List<WakeOnLAN.DeviceAddress> =
        runCatching { NetworkInterface.getNetworkInterfaces()?.toList().orEmpty() }.getOrDefault(emptyList())
            .filter { runCatching { it.isUp && !it.isLoopback }.getOrDefault(false) }
            .flatMap { it.interfaceAddresses }
            .filter { it.address is Inet4Address }
            .mapNotNull { entry -> entry.address.hostAddress?.let { WakeOnLAN.DeviceAddress(it, entry.networkPrefixLength.toInt()) } }
}
