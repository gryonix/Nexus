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
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.app.ui.design.IOSSwitch
import androidx.compose.foundation.layout.size
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.shell.ServerSection
import com.skaymer.gryonixnexus.app.shell.ServerSectionSettings

@Composable
fun ServerSectionsDialog(
    settings: ServerSectionSettings,
    available: List<ServerSection>,
    deploymentID: String,
    onDismiss: () -> Unit,
) {
    val order by settings.order.collectAsState()
    val hidden by settings.hidden.collectAsState()
    val start by settings.startSection.collectAsState()
    hidden[deploymentID]

    IOSSheet(
        title = stringResource(R.string.section_arrange),
        onClose = onDismiss,
        closeLabel = stringResource(R.string.group_done),
    ) {
        val shown = order.filter { it in available }
        GroupedSection {
            shown.forEach { section ->
                val index = order.indexOf(section)
                GroupedRow(
                    showDivider = section != shown.last(),
                    trailing = {
                        MoveButton(Icons.Filled.ArrowUpward, index > 0) {
                            settings.move(section, index - 1)
                        }
                        MoveButton(Icons.Filled.ArrowDownward, index < order.size - 1) {
                            settings.move(section, index + 1)
                        }
                        IOSSwitch(
                            checked = settings.isVisible(section, deploymentID),
                            enabled = !settings.isVisible(section, deploymentID) ||
                                settings.canHide(section, deploymentID, available),
                            onCheckedChange = {
                                settings.setVisible(it, section, deploymentID, available)
                            },
                        )
                    },
                ) {
                    RowLabel(stringResource(section.titleRes))
                }
            }
        }
        GroupedSection(
            header = stringResource(R.string.section_opens_on),
            note = stringResource(R.string.section_arrange_footer),
        ) {
            ServerSection.entries.forEach { section ->
                CheckRow(
                    title = stringResource(section.titleRes),
                    checked = section == start,
                    onClick = { settings.setStartSection(section) },
                    showDivider = section != ServerSection.entries.last(),
                )
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
