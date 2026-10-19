package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.servercontrol.BastionHop
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.FallbackAddress
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint

@Composable
fun BastionPickerSheet(
    selection: BastionHop?,
    fleet: List<Deployment>,
    onSelect: (BastionHop?) -> Unit,
    onDismiss: () -> Unit,
) {
    var host by remember { mutableStateOf(selection?.manual?.host.orEmpty()) }
    var port by remember { mutableStateOf((selection?.manual?.port ?: 22).toString()) }
    var user by remember { mutableStateOf(selection?.manual?.user ?: "root") }

    IOSSheet(
        title = stringResource(R.string.server_bastion),
        onClose = onDismiss,
        closeLabel = stringResource(R.string.group_cancel),
    ) {
        GroupedSection(note = stringResource(R.string.server_bastion_note)) {
            ValueRow(
                title = stringResource(R.string.server_bastion_none),
                value = if (selection == null) "✓" else null,
                onClick = { onSelect(null) },
                showDivider = false,
            )
        }
        if (fleet.isNotEmpty()) {
            GroupedSection(
                header = stringResource(R.string.server_bastion_fleet),
                note = stringResource(R.string.server_bastion_fleet_note),
            ) {
                fleet.forEachIndexed { index, deployment ->
                    ValueRow(
                        title = deployment.name,
                        subtitle = deployment.entry.host,
                        value = if (selection?.fleetServerID == deployment.id) "✓" else null,
                        onClick = { onSelect(BastionHop(fleetServerID = deployment.id)) },
                        showDivider = index != fleet.lastIndex,
                    )
                }
            }
        }
        GroupedSection(
            header = stringResource(R.string.server_bastion_manual),
            note = stringResource(R.string.server_bastion_manual_note),
        ) {
            FieldRow(
                label = stringResource(R.string.host_label),
                value = host,
                placeholder = "jump.example.com",
                onValueChange = { host = it },
            )
            FieldRow(
                label = stringResource(R.string.port_label),
                value = port,
                onValueChange = { port = it.filter(Char::isDigit) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            )
            FieldRow(
                label = stringResource(R.string.user_label),
                value = user,
                placeholder = "root",
                onValueChange = { user = it },
            )
            val endpoint = HostEndpoint(host.trim(), port.toIntOrNull() ?: 22, user.trim())
            ActionRow(
                text = stringResource(R.string.server_bastion_use_host),
                enabled = endpoint.isValid,
                showDivider = false,
                onClick = { onSelect(BastionHop(manual = endpoint)) },
            )
        }
    }
}

/** Where to try when the usual address does not answer */
@Composable
fun FallbackAddressSheet(
    fallback: FallbackAddress?,
    fleet: List<Deployment>,
    primary: HostEndpoint,
    onApply: (FallbackAddress?) -> Unit,
    onDismiss: () -> Unit,
) {
    var host by remember { mutableStateOf(fallback?.host.orEmpty()) }
    var port by remember { mutableStateOf((fallback?.port ?: primary.port).toString()) }
    var bastion by remember { mutableStateOf(fallback?.bastion) }
    var pickingBastion by remember { mutableStateOf(false) }

    IOSSheet(
        title = stringResource(R.string.server_fallback),
        onClose = onDismiss,
        closeLabel = stringResource(R.string.group_cancel),
        action = SheetAction(
            title = stringResource(R.string.save),
            onSelect = {
                val candidate = FallbackAddress(
                    host = host.trim(),
                    port = port.toIntOrNull()?.takeIf { it != primary.port },
                    bastion = bastion,
                )
                onApply(if (candidate.isUsable) candidate else null)
            },
        ),
    ) {
        GroupedSection(note = stringResource(R.string.server_fallback_note)) {
            FieldRow(
                label = stringResource(R.string.host_label),
                value = host,
                placeholder = primary.host,
                onValueChange = { host = it },
            )
            FieldRow(
                label = stringResource(R.string.port_label),
                value = port,
                placeholder = primary.port.toString(),
                onValueChange = { port = it.filter(Char::isDigit) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            )
            ValueRow(
                title = stringResource(R.string.server_bastion),
                value = bastionSummary(bastion, fleet),
                onClick = { pickingBastion = true },
                showDivider = false,
            )
        }
        if (fallback != null) {
            GroupedSection {
                ActionRow(
                    text = stringResource(R.string.server_fallback_remove),
                    danger = true,
                    showDivider = false,
                    onClick = { onApply(null) },
                )
            }
        }
        if (host.isBlank() && bastion == null) {
            Column {
                Text(
                    stringResource(R.string.server_fallback_empty),
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
        }
    }

    if (pickingBastion) {
        BastionPickerSheet(
            selection = bastion,
            fleet = fleet,
            onSelect = { bastion = it; pickingBastion = false },
            onDismiss = { pickingBastion = false },
        )
    }
}

/** What a bastion row says when it is closed */
@Composable
fun bastionSummary(hop: BastionHop?, fleet: List<Deployment>): String {
    if (hop == null || !hop.isUsable) return stringResource(R.string.server_bastion_none)
    hop.fleetServerID?.let { id ->
        return fleet.firstOrNull { it.id == id }?.name
            ?: stringResource(R.string.server_bastion_missing)
    }
    return hop.manual?.host ?: stringResource(R.string.server_bastion_none)
}

/** What the fallback row says when it is closed */
@Composable
fun fallbackSummary(fallback: FallbackAddress?): String {
    if (fallback == null || !fallback.isUsable) {
        return stringResource(R.string.server_bastion_none)
    }
    val host = fallback.host.trim()
    return host.ifEmpty { stringResource(R.string.server_fallback_through_bastion) }
}
