package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.metrics.EnergySettings
import com.skaymer.gryonixnexus.app.metrics.EnergySummary
import com.skaymer.gryonixnexus.app.metrics.HistoryRange
import com.skaymer.gryonixnexus.app.metrics.HistoryViewModel
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

/** Power now, energy per day and month, and cost */
@Composable
fun EnergyScreen(history: HistoryViewModel, server: Deployment, host: SSHHostID) {
    val energy = (LocalContext.current.applicationContext as GryonixApplication).energy
    val now = remember { history.detached() }
    val hourly = remember { history.detached() }
    val daily = remember { history.detached() }
    DisposableEffect(server.id, host) {
        now.show(server, host, HistoryRange.TEN_MINUTES)
        hourly.show(server, host, HistoryRange.TWELVE_DAYS)
        daily.show(server, host, HistoryRange.SIX_MONTHS)
        onDispose { listOf(now, hourly, daily).forEach { it.stop() } }
    }
    val nowState by now.state.collectAsState()
    val hourlyState by hourly.state.collectAsState()
    val dailyState by daily.state.collectAsState()
    val summary = EnergySummary.of(nowState.points, hourlyState.points, dailyState.points)
    var revision by remember { mutableStateOf(0) }

    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item { EnergyNowSection(summary) }
        item { key(revision) { EnergyCostSection(summary, energy) } }
        item { EnergyDaysSection(summary) }
        item { EnergyPriceSection(energy) { revision++ } }
        item { EnergyEstimateSection(energy, server, host, summary.isMeasured) }
    }
}

@Composable
private fun EnergyNowSection(summary: EnergySummary) {
    GroupedSection(header = stringResource(R.string.energy_now), footer = sourceText(summary.latest?.powerSource)) {
        GroupedRow(showDivider = false) {
            Text(
                summary.latest?.powerWatts?.let { watts(it) } ?: "—",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.SemiBold,
                color = Gryonix.colors.label,
            )
        }
    }
}

@Composable
private fun watts(value: Double): String =
    stringResource(R.string.energy_watts, if (value < 10) "%.1f".format(value) else value.toInt().toString())

@Composable
private fun kilowattHours(value: Double): String =
    stringResource(R.string.energy_kwh, if (value < 10) "%.2f".format(value) else "%.1f".format(value))

@Composable
private fun sourceText(source: String?): String = stringResource(
    when (source) {
        "rapl+estimate" -> R.string.energy_source_rapl_completed
        "hwmon+estimate" -> R.string.energy_source_hwmon_completed
        "pi+estimate" -> R.string.energy_source_pi_completed
        "rapl" -> R.string.energy_source_rapl
        "hwmon" -> R.string.energy_source_hwmon
        "ipmi" -> R.string.energy_source_ipmi
        "ups" -> R.string.energy_source_ups
        "pi" -> R.string.energy_source_pi
        else -> R.string.energy_source_parts
    }
)

@Composable
private fun EnergyCostSection(summary: EnergySummary, energy: EnergySettings) {
    GroupedSection(header = stringResource(R.string.energy_cost), note = stringResource(R.string.energy_cost_note)) {
        val rows = listOfNotNull(
            R.string.energy_today to summary.today,
            R.string.energy_month_so_far to summary.monthSoFar,
            R.string.energy_forecast to summary.monthForecast,
            summary.lastMonth?.let { R.string.energy_last_month to it },
        )
        rows.forEach { (title, value) ->
            ValueRow(
                title = stringResource(title),
                value = energy.cost(value) + "  ·  " + kilowattHours(value),
                onClick = null,
                showDivider = title != rows.last().first,
            )
        }
    }
}

@Composable
private fun EnergyDaysSection(summary: EnergySummary) {
    GroupedSection(header = stringResource(R.string.energy_last_30_days)) {
        val peak = summary.days.maxOfOrNull { it.second } ?: 0.0
        GroupedRow(showDivider = false) {
            if (peak <= 0) {
                Text(stringResource(R.string.energy_no_history), color = Gryonix.colors.secondaryLabel)
            } else {
                val bar = Color(0xFFFFCC00)
                Canvas(Modifier.fillMaxWidth().height(140.dp).padding(vertical = 8.dp)) {
                    val width = size.width / summary.days.size
                    summary.days.forEachIndexed { index, (_, value) ->
                        val height = (value / peak * size.height).toFloat()
                        drawRect(bar, Offset(index * width + width * 0.15f, size.height - height),
                            Size(width * 0.7f, height))
                    }
                }
            }
        }
    }
}

@Composable
private fun EnergyPriceSection(energy: EnergySettings, onChange: () -> Unit) {
    var price by remember { mutableStateOf(energy.pricePerKWh.toString()) }
    var currency by remember { mutableStateOf(energy.currencyCode) }
    GroupedSection(header = stringResource(R.string.energy_price)) {
        FieldRow(
            label = stringResource(R.string.energy_price_per_kwh),
            value = price,
            onValueChange = { typed ->
                price = typed
                typed.replace(',', '.').toDoubleOrNull()?.let { energy.pricePerKWh = it; onChange() }
            },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        )
        FieldRow(
            label = stringResource(R.string.energy_currency),
            value = currency,
            onValueChange = { typed ->
                currency = typed.uppercase().take(3)
                if (currency.length == 3) { energy.currencyCode = currency; onChange() }
            },
            showDivider = false,
        )
    }
}
