package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import com.skaymer.gryonixnexus.app.shell.ServerSection
import com.skaymer.gryonixnexus.app.shell.ServerSectionSettings
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl

@Composable
fun ServerSectionsStrip(
    sections: List<ServerSection>,
    available: List<ServerSection>,
    current: ServerSection,
    settings: ServerSectionSettings,
    deploymentID: String,
    onSelect: (ServerSection) -> Unit,
    onArrange: () -> Unit,
) {
    if (sections.size <= 1) return
    var menuFor by remember { mutableStateOf<ServerSection?>(null) }

    Box(
        Modifier.fillMaxWidth()
            .background(Gryonix.colors.barBackground)
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        IOSSegmentedControl(
            segments = sections,
            selected = current,
            label = { stringResource(it.titleRes) },
            onSelect = onSelect,
            onLongPress = { menuFor = it },
        )
        val held = menuFor
        DropdownMenu(expanded = held != null, onDismissRequest = { menuFor = null }) {
            if (held != null && settings.canHide(held, deploymentID, available)) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.section_hide)) },
                    onClick = {
                        menuFor = null
                        settings.setVisible(false, held, deploymentID, available)
                    },
                )
            }
            DropdownMenuItem(
                text = { Text(stringResource(R.string.section_arrange)) },
                onClick = {
                    menuFor = null
                    onArrange()
                },
            )
        }
    }
}
