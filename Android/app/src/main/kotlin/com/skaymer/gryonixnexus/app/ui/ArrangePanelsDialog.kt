package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.metrics.MetricPanel
import com.skaymer.gryonixnexus.app.metrics.MetricPanelStore
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.servercontrol.Deployment

@Composable
fun ArrangePanelsDialog(
    panels: MetricPanelStore,
    shown: List<MetricPanel>,
    servers: List<Deployment>,
    onDismiss: () -> Unit,
) {
    val stored by panels.panels.collectAsState()

    IOSSheet(
        title = stringResource(R.string.metrics_arrange_panels),
        onClose = onDismiss,
        closeLabel = stringResource(R.string.group_done),
    ) {
        GroupedSection {
            shown.forEachIndexed { index, panel ->
                GroupedRow(
                    showDivider = index != shown.lastIndex,
                    trailing = {
                        MoveArrow(Icons.Filled.ArrowUpward, index > 0) {
                            panels.reorder(movedWithinView(stored, shown, index, -1))
                        }
                        MoveArrow(Icons.Filled.ArrowDownward, index < shown.lastIndex) {
                            panels.reorder(movedWithinView(stored, shown, index, 1))
                        }
                    },
                ) {
                    RowLabel(
                        title = servers.firstOrNull { it.id == panel.deploymentID }?.name
                            ?: stringResource(R.string.metrics_unknown_server),
                        subtitle = panel.metrics.joinToString(", ") { it.name.lowercase() } +
                            "  ·  " + panel.range.rawValue,
                    )
                }
            }
        }
    }
}

@Composable
private fun MoveArrow(icon: ImageVector, enabled: Boolean, onClick: () -> Unit) {
    IconButton(onClick = onClick, enabled = enabled, modifier = Modifier.size(30.dp)) {
        Icon(
            icon,
            contentDescription = null,
            tint = if (enabled) Gryonix.colors.accent else Gryonix.colors.tertiaryLabel,
            modifier = Modifier.size(20.dp),
        )
    }
}
