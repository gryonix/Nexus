package com.skaymer.gryonixnexus.app.metrics

import android.content.SharedPreferences
import com.skaymer.gryonixnexus.servercontrol.EnergyProfile
import com.skaymer.gryonixnexus.servercontrol.PowerEstimate
import com.skaymer.gryonixnexus.servercontrol.PowerHardware
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.time.Duration.Companion.seconds
import java.util.Currency
import java.util.Locale
import kotlinx.serialization.json.Json

/** Electricity price and each server's estimate profile */
class EnergySettings(private val preferences: SharedPreferences) {
    var pricePerKWh: Double
        get() = if (preferences.contains(PRICE)) preferences.getFloat(PRICE, 0.30f).toDouble()
        else TYPICAL_PRICE[currencyCode] ?: 0.30
        set(value) = preferences.edit().putFloat(PRICE, value.toFloat()).apply()

    var currencyCode: String
        get() = preferences.getString(CURRENCY, null)
            ?: runCatching { Currency.getInstance(Locale.getDefault()).currencyCode }.getOrDefault("EUR")
        set(value) = preferences.edit().putString(CURRENCY, value).apply()

    /** Typed watts, else the parts estimate, else a guess */
    fun profile(serverId: String, host: SSHHostID, cores: Int? = null): EnergyProfile =
        typed(serverId, host) ?: estimate(serverId, host)?.profile ?: EnergyProfile.guess(cores ?: 4)

    private fun typed(serverId: String, host: SSHHostID): EnergyProfile? =
        preferences.getString(key(serverId, host), null)
            ?.let { runCatching { Json.decodeFromString(EnergyProfile.serializer(), it) }.getOrNull() }

    fun isTyped(serverId: String, host: SSHHostID): Boolean = typed(serverId, host) != null

    fun clearProfile(serverId: String, host: SSHHostID) {
        preferences.edit().remove(key(serverId, host)).apply()
    }

    fun estimate(serverId: String, host: SSHHostID): PowerEstimate? =
        preferences.getString(detectedKey(serverId, host), null)
            ?.let { runCatching { Json.decodeFromString(PowerEstimate.serializer(), it) }.getOrNull() }

    fun setEstimate(estimate: PowerEstimate, serverId: String, host: SSHHostID) {
        preferences.edit()
            .putString(detectedKey(serverId, host), Json.encodeToString(PowerEstimate.serializer(), estimate))
            .apply()
    }

    /** Hardware is read again after a week */
    fun needsDetection(serverId: String, host: SSHHostID, nowSeconds: Long = System.currentTimeMillis() / 1_000): Boolean {
        val found = estimate(serverId, host) ?: return true
        return nowSeconds - found.detectedAtEpochSeconds > 7 * 86_400
    }

    /** Reads the host's parts weekly; failures keep the old estimate */
    suspend fun detect(serverId: String, host: SSHHostID, runner: SSHCommandRunner) {
        if (!needsDetection(serverId, host)) return
        val output = runCatching { runner.run(PowerHardware.PROBE_COMMAND, host, 20.seconds).stdout }.getOrNull()
        val hardware = output?.let(PowerHardware::parse) ?: return
        setEstimate(PowerEstimate.of(hardware), serverId, host)
    }

    fun setProfile(profile: EnergyProfile, serverId: String, host: SSHHostID) {
        preferences.edit().putString(key(serverId, host), Json.encodeToString(EnergyProfile.serializer(), profile)).apply()
    }

    fun cost(kilowattHours: Double): String {
        val format = java.text.NumberFormat.getCurrencyInstance()
        runCatching { format.currency = Currency.getInstance(currencyCode) }
        return format.format(kilowattHours * pricePerKWh)
    }

    private fun key(serverId: String, host: SSHHostID) = "energy.profile.$serverId.$host"

    private fun detectedKey(serverId: String, host: SSHHostID) = "energy.detected.$serverId.$host"

    companion object {
        /** A household price per kWh to start from, by currency */
        val TYPICAL_PRICE = mapOf(
            "EUR" to 0.30, "USD" to 0.17, "GBP" to 0.25, "CHF" to 0.30, "PLN" to 1.0, "CZK" to 6.0,
            "SEK" to 1.5, "DKK" to 2.2, "NOK" to 1.5, "HUF" to 70.0, "RON" to 1.3, "BGN" to 0.3,
            "UAH" to 4.3, "RUB" to 6.5, "JPY" to 31.0, "CNY" to 0.6,
        )
        private const val PRICE = "energy.pricePerKWh"
        private const val CURRENCY = "energy.currency"
    }
}
