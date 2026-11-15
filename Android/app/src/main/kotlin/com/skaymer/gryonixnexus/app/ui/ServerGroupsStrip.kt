package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.FormSheet
import com.skaymer.gryonixnexus.app.ui.design.AlertFields
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ServerGroups

@Composable
fun ServerGroupsStrip(
    deployments: List<Deployment>,
    selected: String?,
    onSelect: (String?) -> Unit,
    fleet: FleetRepository,
    onReorder: () -> Unit,
    /** Writing several servers to files in one go */
    onExportSeveral: () -> Unit,
    /** Writing these groups and their servers to one file */
    onExportGroups: (List<String>) -> Unit,
    onImport: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val order by fleet.groupOrder.collectAsState()
    val groups = remember(deployments, order) { ServerGroups.known(deployments, order) }

    val shown = groups.size >= 2
    LaunchedEffect(deployments, selected, shown) {
        val reachable = if (shown) ServerGroups.reachable(selected, deployments) else null
        if (reachable != selected) onSelect(reachable)
    }
    if (!shown) return

    var menuFor by remember { mutableStateOf<String?>(null) }
    var renaming by remember { mutableStateOf<String?>(null) }
    var naming by remember { mutableStateOf(false) }
    var filling by remember { mutableStateOf<String?>(null) }

    val entries = listOf<String?>(null) + groups
    GroupTrack(entries.size, modifier) { entry ->
        val group = entries[entry]
        GroupEntry(
            title = group ?: stringResource(R.string.group_all),
            selected = selected == group,
            onClick = { onSelect(group) },
            onLongClick = { menuFor = group ?: "" },
            menuOpen = menuFor == (group ?: ""),
            onDismiss = { menuFor = null },
        ) {
            if (group == null) {
                AllGroupsMenu(
                    hasGroups = groups.isNotEmpty(),
                    onClose = { menuFor = null },
                    onNew = { naming = true },
                    onReorder = onReorder,
                    onExportSeveral = onExportSeveral,
                    onExportGroups = { onExportGroups(groups) },
                    onImport = onImport,
                )
            } else {
                GroupMenu(
                    group = group,
                    place = groups.indexOf(group),
                    count = groups.size,
                    deployments = deployments,
                    fleet = fleet,
                    onClose = { menuFor = null },
                    onRename = { renaming = group },
                    onNew = { naming = true },
                    onExport = { onExportGroups(listOf(group)) },
                )
            }
        }
    }

    renaming?.let { old ->
        NameEditSheet(
            title = stringResource(R.string.group_rename),
            label = stringResource(R.string.group_name),
            initial = old,
            valid = { ServerGroups.clean(it) != null },
            onSave = { typed ->
                ServerGroups.clean(typed)?.let { name ->
                    fleet.renameGroup(old, name)
                    if (selected == old) onSelect(name)
                }
            },
            onClose = { renaming = null },
        )
    }

    if (naming) {
        NameEditSheet(
            title = stringResource(R.string.group_new_title),
            label = stringResource(R.string.group_name),
            initial = "",
            valid = { ServerGroups.clean(it) != null },
            onSave = { filling = ServerGroups.clean(it) },
            onClose = { naming = false },
        )
    }

    filling?.let { group ->
        GroupMembershipDialog(
            group = group,
            deployments = deployments,
            onDismiss = { filling = null },
            onSave = { chosen ->
                fleet.setGroupMembership(group, chosen)
                if (chosen.isNotEmpty()) onSelect(group)
                filling = null
            }
        )
    }
}

/** One group's long-press menu */
@Composable
private fun GroupMenu(
    group: String,
    place: Int,
    count: Int,
    deployments: List<Deployment>,
    fleet: FleetRepository,
    onClose: () -> Unit,
    onRename: () -> Unit,
    onNew: () -> Unit,
    onExport: () -> Unit,
) {
    deployments.forEach { deployment ->
        val inside = ServerGroups.members(group, listOf(deployment)).isNotEmpty()
        DropdownMenuItem(
            text = { Text(deployment.name) },
            leadingIcon = {
                if (inside) {
                    Icon(Icons.Filled.Check, contentDescription = null)
                } else {
                    Box(Modifier.size(24.dp))
                }
            },
            onClick = {
                fleet.setGroupMember(deployment.id, group, !inside)
                onClose()
            }
        )
    }
    HorizontalDivider()
    if (place > 0) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.group_move_left)) },
            onClick = { onClose(); fleet.moveGroup(group, -1) }
        )
    }
    if (place in 0 until count - 1) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.group_move_right)) },
            onClick = { onClose(); fleet.moveGroup(group, 1) }
        )
    }
    DropdownMenuItem(
        text = { Text(stringResource(R.string.group_export)) },
        onClick = { onClose(); onExport() }
    )
    HorizontalDivider()
    DropdownMenuItem(
        text = { Text(stringResource(R.string.group_rename)) },
        onClick = { onClose(); onRename() }
    )
    NewGroupItem { onClose(); onNew() }
    DropdownMenuItem(
        text = {
            Text(
                stringResource(R.string.group_delete),
                color = MaterialTheme.colorScheme.error
            )
        },
        onClick = { onClose(); fleet.deleteGroup(group) }
    )
}

@Composable
private fun NewGroupItem(onClick: () -> Unit) {
    DropdownMenuItem(text = { Text(stringResource(R.string.group_new)) }, onClick = onClick)
}

/** The grey capsule the segments sit in, as on iOS */
@Composable
private fun GroupTrack(count: Int, modifier: Modifier, entry: @Composable (Int) -> Unit) {
    val track = Modifier
        .padding(horizontal = 16.dp, vertical = 8.dp)
        .fillMaxWidth()
        .clip(RoundedCornerShape(percent = 50))
        .background(Gryonix.colors.trackFill)
        .padding(3.dp)
    if (count <= EVEN_SEGMENTS) {
        Row(modifier.then(track)) {
            repeat(count) { index -> Box(Modifier.weight(1f)) { entry(index) } }
        }
    } else {
        LazyRow(modifier.then(track)) {
            items(count) { index -> entry(index) }
        }
    }
}

private const val EVEN_SEGMENTS = 4

/** One segment and its long-press menu */
@Composable
private fun GroupEntry(
    title: String,
    selected: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    menuOpen: Boolean,
    onDismiss: () -> Unit,
    menu: @Composable () -> Unit,
) {
    Box {
        GroupSegment(title, selected, onClick, onLongClick)
        DropdownMenu(expanded = menuOpen, onDismissRequest = onDismiss) { menu() }
    }
}

/** The menu of "All": new group, order, files */
@Composable
private fun AllGroupsMenu(
    hasGroups: Boolean,
    onClose: () -> Unit,
    onNew: () -> Unit,
    onReorder: () -> Unit,
    onExportSeveral: () -> Unit,
    onExportGroups: () -> Unit,
    onImport: () -> Unit,
) {
    NewGroupItem { onClose(); onNew() }
    DropdownMenuItem(text = { Text(stringResource(R.string.reorder_servers)) }, onClick = { onClose(); onReorder() })
    DropdownMenuItem(text = { Text(stringResource(R.string.export_several)) }, onClick = { onClose(); onExportSeveral() })
    if (hasGroups) {
        DropdownMenuItem(text = { Text(stringResource(R.string.group_export_all)) }, onClick = { onClose(); onExportGroups() })
    }
    DropdownMenuItem(text = { Text(stringResource(R.string.group_import)) }, onClick = { onClose(); onImport() })
}

/** One segment: white when chosen */
@Composable
private fun GroupSegment(
    title: String,
    selected: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val colors = Gryonix.colors
    val shape = RoundedCornerShape(percent = 50)
    Text(
        title,
        style = MaterialTheme.typography.bodyMedium,
        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        color = colors.label,
        maxLines = 1,
        textAlign = TextAlign.Center,
        modifier = Modifier
            .fillMaxWidth()
            .then(if (selected) Modifier.shadow(2.dp, shape) else Modifier)
            .clip(shape)
            .background(if (selected) colors.cardBackground else Color.Transparent)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 18.dp, vertical = 9.dp),
    )
}

/** Which servers a group holds */
@Composable
private fun GroupMembershipDialog(
    group: String,
    deployments: List<Deployment>,
    onDismiss: () -> Unit,
    onSave: (Set<String>) -> Unit,
) {
    var chosen by remember(group) {
        mutableStateOf(ServerGroups.members(group, deployments).map { it.id }.toSet())
    }
    FormSheet(
        title = group,
        onDismiss = onDismiss,
        message = stringResource(R.string.group_members_footer),
        actions = listOf(
            AlertAction(stringResource(R.string.group_cancel), onSelect = onDismiss),
            AlertAction(
                stringResource(R.string.group_done),
                preferred = true,
                onSelect = { onSave(chosen) },
            ),
        ),
    ) {
        AlertFields {
            deployments.forEach { deployment ->
                CheckRow(
                    title = deployment.name,
                    checked = deployment.id in chosen,
                    onClick = {
                        chosen = if (deployment.id in chosen) {
                            chosen - deployment.id
                        } else {
                            chosen + deployment.id
                        }
                    },
                    showDivider = deployment != deployments.last(),
                )
            }
        }
    }
}
