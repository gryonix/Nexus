package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.agentcontrol.VPNDNSPriority
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.vpn.LocalDNS
import com.skaymer.gryonixnexus.app.vpn.VPNClientsViewModel
import com.skaymer.gryonixnexus.app.vpn.VPNDNSPriorityEditing
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** The order the server's DNS relay asks resolvers in */
@Composable
fun VPNDNSPrioritySection(
    server: Deployment,
    clients: VPNClientsViewModel,
    priority: VPNDNSPriority,
    local: LocalDNS,
) {
    var typing by remember { mutableStateOf(false) }
    val order = priority.resolvers
    val save: (List<String>) -> Unit = { changed -> if (changed != order) clients.setDNSPriority(server, changed) }
    GroupedSection(
        header = stringResource(R.string.dns_order_header),
        note = stringResource(R.string.dns_order_note) + " " + stringResource(R.string.dns_order_footer),
    ) {
        order.forEachIndexed { index, entry ->
            val last = index == order.lastIndex && !VPNDNSPriorityEditing.canAdd(order)
            PriorityRow(index, entry, priority, local, showDivider = !last, save)
        }
        if (VPNDNSPriorityEditing.canAdd(order)) AddResolverRow(order, local, save, onTyping = { typing = true })
    }
    if (typing) {
        TypedResolverAlert(
            onAdd = { address -> save(VPNDNSPriorityEditing.add(address, order)) },
            onDismiss = { typing = false },
        )
    }
}

/** What one entry is called in the list */
@Composable
fun priorityEntryName(entry: String, local: LocalDNS): String =
    when (val described = VPNDNSPriorityEditing.describe(entry)) {
        VPNDNSPriorityEditing.Entry.Local -> localName(local)
        is VPNDNSPriorityEditing.Entry.Preset ->
            stringResource(R.string.dns_order_preset, presetName(described.preset), described.address)
        is VPNDNSPriorityEditing.Entry.Address -> described.address
    }

@Composable
private fun PriorityRow(
    index: Int,
    entry: String,
    priority: VPNDNSPriority,
    local: LocalDNS,
    showDivider: Boolean,
    save: (List<String>) -> Unit,
) {
    GroupedRow(
        showDivider = showDivider,
        leading = {
            Text(
                "${index + 1}.",
                style = MaterialTheme.typography.bodyLarge,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.width(24.dp),
            )
        },
        trailing = { PriorityRowMenu(index, priority.resolvers, save) },
    ) {
        PriorityLabel(priorityEntryName(entry, local), answering = priority.isReachable(index))
    }
}

@Composable
private fun RowScope.PriorityLabel(name: String, answering: Boolean) {
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(name, style = MaterialTheme.typography.bodyLarge, color = Gryonix.colors.label)
        if (!answering) {
            Text(
                stringResource(R.string.dns_order_not_answering),
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.warning,
            )
        }
    }
}

/** Move up, move down, remove */
@Composable
private fun PriorityRowMenu(index: Int, order: List<String>, save: (List<String>) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }, modifier = Modifier.size(28.dp)) {
            Icon(
                Icons.Filled.MoreHoriz,
                contentDescription = stringResource(R.string.dns_order_change),
                tint = Gryonix.colors.accent,
            )
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            val pick: (List<String>) -> Unit = { changed -> open = false; save(changed) }
            DropdownMenuItem(
                text = { Text(stringResource(R.string.move_up)) },
                enabled = index > 0,
                onClick = { pick(VPNDNSPriorityEditing.moveUp(index, order)) },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.move_down)) },
                enabled = index < order.lastIndex,
                onClick = { pick(VPNDNSPriorityEditing.moveDown(index, order)) },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.vpn_remove), color = Gryonix.colors.danger) },
                enabled = order.size > 1,
                onClick = { pick(VPNDNSPriorityEditing.remove(index, order)) },
            )
        }
    }
}

/** This server's DNS, public presets, or a typed address */
@Composable
private fun AddResolverRow(order: List<String>, local: LocalDNS, save: (List<String>) -> Unit, onTyping: () -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        ActionRow(text = stringResource(R.string.dns_order_add), onClick = { open = true }, showDivider = false)
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            val candidates = buildList {
                if (VPNDNSPriority.LOCAL !in order) add(VPNDNSPriority.LOCAL)
                VPNDNSPriorityEditing.publicChoices.map { it.addresses.first() }.filterTo(this) { it !in order }
            }
            candidates.forEach { entry ->
                DropdownMenuItem(
                    text = { Text(priorityEntryName(entry, local)) },
                    onClick = {
                        open = false
                        save(VPNDNSPriorityEditing.add(entry, order))
                    },
                )
            }
            DropdownMenuItem(
                text = { Text(stringResource(R.string.dns_order_other)) },
                onClick = {
                    open = false
                    onTyping()
                },
            )
        }
    }
}

/** One resolver address, typed by hand */
@Composable
private fun TypedResolverAlert(onAdd: (String) -> Unit, onDismiss: () -> Unit) {
    var text by remember { mutableStateOf("") }
    val address = VPNDNSPriorityEditing.typed(text)
    IOSAlert(
        title = stringResource(R.string.dns_order_typed_title),
        message = stringResource(R.string.dns_order_typed_message),
        onDismiss = onDismiss,
        actions = listOf(
            AlertAction(stringResource(R.string.vpn_cancel)) { onDismiss() },
            AlertAction(stringResource(R.string.vpn_add), preferred = true, enabled = address != null) {
                address?.let(onAdd)
                onDismiss()
            },
        ),
    ) {
        FieldRow(
            label = stringResource(R.string.dns_servers),
            value = text,
            onValueChange = { text = it },
            placeholder = "1.1.1.1",
            showDivider = false,
        )
    }
}
