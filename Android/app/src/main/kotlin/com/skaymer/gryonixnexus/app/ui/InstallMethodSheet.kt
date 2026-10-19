package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.licensing.LicensePrompt
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.core.Artifact

/** How the chosen services go onto the server */
@Composable
fun InstallMethodSheet(
    services: List<ManagedService>,
    scripts: List<Artifact>,
    title: String = stringResource(R.string.install_start),
    deviceText: String = stringResource(R.string.install_method_device),
    onDevice: () -> Unit,
    onCancel: () -> Unit,
) {
    var opened by remember { mutableStateOf<Artifact?>(null) }
    val clipboard = LocalClipboardManager.current
    IOSSheet(
        title = title,
        onClose = onCancel,
        closeLabel = stringResource(R.string.group_cancel),
    ) {
        GroupedSection(
            header = services.joinToString(", ") { it.displayName },
            footer = stringResource(R.string.install_method_device_note),
        ) {
            ActionRow(
                text = deviceText,
                onClick = { if (LicensePrompt.allow()) onDevice() },
                showDivider = false,
            )
        }
        if (scripts.isNotEmpty()) {
            GroupedSection(
                header = stringResource(R.string.install_method_scripts),
                footer = stringResource(R.string.install_method_scripts_note),
            ) {
                scripts.forEachIndexed { index, artifact ->
                    ActionRow(
                        text = artifact.fileName,
                        onClick = { if (LicensePrompt.allow()) opened = artifact },
                        showDivider = index != scripts.lastIndex,
                    )
                }
            }
        }
    }
    opened?.let { artifact ->
        IOSSheet(
            title = artifact.fileName,
            onClose = { opened = null },
            closeLabel = stringResource(R.string.close),
        ) {
            GroupedSection {
                ActionRow(
                    text = stringResource(R.string.service_logs_copy),
                    onClick = { clipboard.setText(AnnotatedString(artifact.contents)) },
                    showDivider = false,
                )
            }
            ArtifactScreen(artifact)
        }
    }
}
