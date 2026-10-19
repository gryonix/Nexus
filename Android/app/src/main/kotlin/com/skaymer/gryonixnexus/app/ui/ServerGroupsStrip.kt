package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
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
    modifier: Modifier = Modifier,
) {
    val groups = remember(deployments) { ServerGroups.known(deployments) }

    LaunchedEffect(deployments, selected) {
        val reachable = ServerGroups.reachable(selected, deployments)
        if (reachable != selected) onSelect(reachable)
    }

    var menuFor by remember { mutableStateOf<String?>(null) }
    var renaming by remember { mutableStateOf<String?>(null) }
    var naming by remember { mutableStateOf(false) }
    var nameField by remember { mutableStateOf("") }
    var filling by remember { mutableStateOf<String?>(null) }

    LazyRow(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp)
    ) {
        item {
            Box {
                GroupSegment(
                    title = stringResource(R.string.group_all),
                    selected = selected == null,
                    onClick = { onSelect(null) },
                    onLongClick = { menuFor = "" }
                )
                DropdownMenu(expanded = menuFor == "", onDismissRequest = { menuFor = null }) {
                    NewGroupItem { menuFor = null; nameField = ""; naming = true }
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.reorder_servers)) },
                        onClick = { menuFor = null; onReorder() }
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.export_several)) },
                        onClick = { menuFor = null; onExportSeveral() }
                    )
                }
            }
        }
        items(groups, key = { it }) { group ->
            Box {
                GroupSegment(
                    title = group,
                    selected = selected == group,
                    onClick = { onSelect(group) },
                    onLongClick = { menuFor = group }
                )
                DropdownMenu(
                    expanded = menuFor == group,
                    onDismissRequest = { menuFor = null }
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
                                menuFor = null
                            }
                        )
                    }
                    HorizontalDivider()
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.group_rename)) },
                        onClick = { menuFor = null; nameField = group; renaming = group }
                    )
                    NewGroupItem { menuFor = null; nameField = ""; naming = true }
                    DropdownMenuItem(
                        text = {
                            Text(
                                stringResource(R.string.group_delete),
                                color = MaterialTheme.colorScheme.error
                            )
                        },
                        onClick = { menuFor = null; fleet.deleteGroup(group) }
                    )
                }
            }
        }
    }

    renaming?.let { old ->
        GroupNameDialog(
            title = stringResource(R.string.group_rename),
            confirm = stringResource(R.string.group_rename_confirm),
            value = nameField,
            onValue = { nameField = it },
            onDismiss = { renaming = null },
            onConfirm = {
                ServerGroups.clean(nameField)?.let { name ->
                    fleet.renameGroup(old, name)
                    if (selected == old) onSelect(name)
                }
                renaming = null
            }
        )
    }

    if (naming) {
        GroupNameDialog(
            title = stringResource(R.string.group_new_title),
            confirm = stringResource(R.string.group_next),
            value = nameField,
            onValue = { nameField = it },
            onDismiss = { naming = false },
            onConfirm = {
                filling = ServerGroups.clean(nameField)
                naming = false
            }
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

@Composable
private fun NewGroupItem(onClick: () -> Unit) {
    DropdownMenuItem(text = { Text(stringResource(R.string.group_new)) }, onClick = onClick)
}

/** One segment */
@Composable
private fun GroupSegment(
    title: String,
    selected: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val colors = Gryonix.colors
    Text(
        title,
        style = MaterialTheme.typography.bodySmall,
        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        color = if (selected) Color.White else colors.label,
        maxLines = 1,
        modifier = Modifier
            .clip(RoundedCornerShape(percent = 50))
            .background(if (selected) colors.accent else colors.trackFill)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 14.dp, vertical = 7.dp),
    )
}

@Composable
private fun GroupNameDialog(
    title: String,
    confirm: String,
    value: String,
    onValue: (String) -> Unit,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    IOSAlert(
        title = title,
        onDismiss = onDismiss,
        actions = listOf(
            AlertAction(stringResource(R.string.group_cancel), onSelect = onDismiss),
            AlertAction(confirm, preferred = true, onSelect = onConfirm),
        ),
    ) {
        AlertFields {
            FieldRow(
                label = stringResource(R.string.group_name),
                value = value,
                onValueChange = onValue,
                showDivider = false,
            )
        }
    }
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
    IOSAlert(
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
