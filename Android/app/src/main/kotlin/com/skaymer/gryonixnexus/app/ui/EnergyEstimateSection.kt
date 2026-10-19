package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.metrics.EnergySettings
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.EnergyProfile
import com.skaymer.gryonixnexus.servercontrol.PowerEstimate
import com.skaymer.gryonixnexus.servercontrol.PowerPart
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

/** Parts and watts used when there is no sensor */
@Composable
internal fun EnergyEstimateSection(energy: EnergySettings, server: Deployment, host: SSHHostID, measured: Boolean) {
    var revision by remember { mutableStateOf(0) }
    val estimate = energy.estimate(server.id, host)
    val typed = remember(revision) { energy.isTyped(server.id, host) }
    GroupedSection(
        header = stringResource(R.string.energy_estimate),
        footer = stringResource(footer(measured, estimate)),
    ) {
        estimate?.parts?.forEach { PowerPartRow(it) }
        key(revision, estimate?.detectedAtEpochSeconds) {
            WattsFields(energy, server, host, onTyped = { if (!typed) revision++ })
        }
        if (typed && estimate != null) {
            ActionRow(
                text = stringResource(R.string.energy_use_parts_estimate),
                onClick = { energy.clearProfile(server.id, host); revision++ },
                showDivider = false,
            )
        }
    }
}

private fun footer(measured: Boolean, estimate: PowerEstimate?): Int = when {
    measured -> R.string.energy_estimate_measured
    estimate?.isVirtual == true -> R.string.energy_estimate_virtual_note
    estimate != null -> R.string.energy_estimate_parts_note
    else -> R.string.energy_estimate_note
}

@Composable
private fun WattsFields(energy: EnergySettings, server: Deployment, host: SSHHostID, onTyped: () -> Unit) {
    val start = remember { energy.profile(server.id, host) }
    var idle by remember { mutableStateOf(start.idleWatts.toString()) }
    var peak by remember { mutableStateOf(start.peakWatts.toString()) }
    fun save() {
        val idleWatts = idle.replace(',', '.').toDoubleOrNull() ?: return
        val peakWatts = peak.replace(',', '.').toDoubleOrNull() ?: return
        energy.setProfile(EnergyProfile(idleWatts, peakWatts), server.id, host)
        onTyped()
    }
    FieldRow(
        label = stringResource(R.string.energy_idle),
        value = idle,
        onValueChange = { idle = it; save() },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
    )
    FieldRow(
        label = stringResource(R.string.energy_full_load),
        value = peak,
        onValueChange = { peak = it; save() },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        showDivider = false,
    )
}

/** One estimate part with its idle and full-load watts */
@Composable
private fun PowerPartRow(part: PowerPart) {
    ValueRow(
        title = partTitle(part),
        value = stringResource(R.string.energy_watts_range, number(part.idleWatts), number(part.peakWatts)),
        onClick = null,
        subtitle = partDetail(part),
    )
}

private fun number(value: Double): String =
    if (value < 10) "%.1f".format(value) else Math.round(value).toString()

@Composable
private fun partTitle(part: PowerPart): String = when (part.kind) {
    PowerPart.Kind.PROCESSOR, PowerPart.Kind.SINGLE_BOARD ->
        part.name.ifEmpty { stringResource(R.string.energy_part_processor) }
    PowerPart.Kind.MEMORY -> stringResource(R.string.energy_part_memory, part.count)
    PowerPart.Kind.NVME -> stringResource(R.string.energy_part_nvme, part.count)
    PowerPart.Kind.SSD -> stringResource(R.string.energy_part_ssd, part.count)
    PowerPart.Kind.HDD -> stringResource(R.string.energy_part_hdd, part.count)
    PowerPart.Kind.GRAPHICS -> stringResource(R.string.energy_part_graphics, part.count)
    PowerPart.Kind.SERVER_BOARD -> stringResource(R.string.energy_part_server_board)
    PowerPart.Kind.DESKTOP_BOARD -> stringResource(R.string.energy_part_desktop_board)
    PowerPart.Kind.COMPACT_BOARD -> stringResource(R.string.energy_part_compact_board)
    PowerPart.Kind.VIRTUAL_SHARE -> stringResource(R.string.energy_part_virtual_share, part.count)
    PowerPart.Kind.POWER_SUPPLY -> stringResource(R.string.energy_part_power_supply)
}

@Composable
private fun partDetail(part: PowerPart): String? = when (part.kind) {
    PowerPart.Kind.PROCESSOR ->
        if (part.count > 1) stringResource(R.string.energy_part_processors, part.count)
        else stringResource(R.string.energy_part_processor)
    PowerPart.Kind.SINGLE_BOARD -> stringResource(R.string.energy_part_whole_board)
    else -> null
}
