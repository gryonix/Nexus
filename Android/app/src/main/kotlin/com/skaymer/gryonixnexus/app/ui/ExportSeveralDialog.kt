package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** Which servers to write out at once */
@Composable
fun ExportSeveralDialog(
    deployments: List<Deployment>,
    onDismiss: () -> Unit,
    onChosen: (List<Deployment>) -> Unit,
) {
    var chosen by remember { mutableStateOf(emptySet<String>()) }

    IOSSheet(
        title = stringResource(R.string.export_several),
        onClose = onDismiss,
        closeLabel = stringResource(R.string.group_cancel),
        action = SheetAction(
            title = stringResource(R.string.export_server_confirm),
            enabled = chosen.isNotEmpty(),
            destructive = true,
            onSelect = { onChosen(deployments.filter { it.id in chosen }) },
        ),
    ) {
        GroupedSection(footer = stringResource(R.string.export_server_warning)) {
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
