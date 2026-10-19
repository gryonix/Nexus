package com.skaymer.gryonixnexus.app.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.layout.size
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.FleetOrder
import com.skaymer.gryonixnexus.app.servers.FleetRepository

/** The order of the servers, arranged away from the cards */
@Composable
fun ReorderServersDialog(fleet: FleetRepository, onDismiss: () -> Unit) {
    val deployments by fleet.deployments.collectAsState()

    IOSSheet(
        title = stringResource(R.string.reorder_servers),
        onClose = onDismiss,
        closeLabel = stringResource(R.string.group_done),
    ) {
        GroupedSection {
            deployments.forEachIndexed { index, deployment ->
                GroupedRow(
                    showDivider = index != deployments.lastIndex,
                    trailing = {
                        MoveButton(
                            Icons.Filled.ArrowUpward,
                            FleetOrder.canMoveUp(index),
                        ) { fleet.move(index, index - 1) }
                        MoveButton(
                            Icons.Filled.ArrowDownward,
                            FleetOrder.canMoveDown(index, deployments.size),
                        ) { fleet.move(index, index + 1) }
                    },
                ) {
                    RowLabel(deployment.name, deployment.entry.host)
                }
            }
        }
    }
}

@Composable
private fun MoveButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    IconButton(onClick = onClick, enabled = enabled, modifier = Modifier.size(30.dp)) {
        Icon(
            icon,
            contentDescription = null,
            tint = if (enabled) Gryonix.colors.accent else Gryonix.colors.tertiaryLabel,
            modifier = Modifier.size(20.dp),
        )
    }
}
