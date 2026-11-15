package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
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
    val order = priority.resolvers
    val save: (List<String>) -> Unit = { changed -> if (changed != order) clients.setDNSPriority(server, changed) }
    val homeNotFirst = local.isOffered && order.firstOrNull() != VPNDNSPriority.LOCAL
    GroupedSection(
        header = stringResource(R.string.dns_order_header),
        note = stringResource(R.string.dns_order_note) + " " + stringResource(R.string.dns_order_footer),
        footer = if (homeNotFirst) stringResource(R.string.dns_order_home_not_first) else null,
    ) {
        order.forEachIndexed { index, entry ->
            val last = index == order.lastIndex && !VPNDNSPriorityEditing.canAdd(order)
            PriorityRow(index, entry, priority, local, showDivider = !last, save)
        }
        if (VPNDNSPriorityEditing.canAdd(order)) {
            AddResolverRow(order, local, save)
            ResolverAddressRow(order, save)
        }
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
        trailing = {
            if (index == 0) {
                Icon(Icons.Filled.Lock, stringResource(R.string.dns_order_chosen), tint = Gryonix.colors.secondaryLabel)
            } else {
                PriorityRowMenu(index, priority.resolvers, save)
            }
        },
    ) {
        PriorityLabel(priorityEntryName(entry, local), answering = priority.isReachable(index), chosen = index == 0)
    }
}

@Composable
private fun RowScope.PriorityLabel(name: String, answering: Boolean, chosen: Boolean) {
    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(name, style = MaterialTheme.typography.bodyLarge, color = Gryonix.colors.label)
        if (chosen) {
            Text(
                stringResource(R.string.dns_order_chosen),
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.secondaryLabel,
            )
        }
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
                enabled = VPNDNSPriorityEditing.canMoveUp(index),
                onClick = { pick(VPNDNSPriorityEditing.moveUp(index, order)) },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.move_down)) },
                enabled = VPNDNSPriorityEditing.canMoveDown(index, order),
                onClick = { pick(VPNDNSPriorityEditing.moveDown(index, order)) },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.vpn_remove), color = Gryonix.colors.danger) },
                onClick = { pick(VPNDNSPriorityEditing.remove(index, order)) },
            )
        }
    }
}

/** This server's DNS, public presets, or a typed address */
@Composable
private fun AddResolverRow(order: List<String>, local: LocalDNS, save: (List<String>) -> Unit) {
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
        }
    }
}

/** One resolver address, typed in its row */
@Composable
private fun ResolverAddressRow(order: List<String>, save: (List<String>) -> Unit) {
    PendingTextRow(
        label = stringResource(R.string.dns_order_typed_title),
        saved = "",
        placeholder = "1.1.1.1",
        apply = stringResource(R.string.vpn_add),
        clearsAfterApply = true,
        valid = { VPNDNSPriorityEditing.typed(it) != null },
        onApply = { text -> VPNDNSPriorityEditing.typed(text)?.let { save(VPNDNSPriorityEditing.add(it, order)) } },
    )
}
