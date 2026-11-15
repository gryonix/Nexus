package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.FormSheet
import com.skaymer.gryonixnexus.app.ui.design.AlertFields
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.servercontrol.SavedScript
import java.util.UUID

/** Settings, Scripts: the saved snippets */
@Composable
fun ScriptsPage() {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val scripts by app.scripts.scripts.collectAsState()
    var editing by remember { mutableStateOf<SavedScript?>(null) }
    var running by remember { mutableStateOf<SavedScript?>(null) }
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item {
            GroupedSection(footer = stringResource(R.string.scripts_footer)) {
                if (scripts.isEmpty()) {
                    GroupedRow(showDivider = false) {
                        Text(stringResource(R.string.scripts_empty), color = Gryonix.colors.secondaryLabel)
                    }
                }
                scripts.forEach { script ->
                    GroupedRow(showDivider = script != scripts.last(), onClick = { running = script },
                        trailing = { DisclosureChevron() }) {
                        RowLabel(script.name, script.body.lines().first())
                    }
                }
            }
        }
        item {
            GroupedSection {
                ActionRow(stringResource(R.string.scripts_add), showDivider = false,
                    onClick = { editing = SavedScript(UUID.randomUUID().toString(), "", "") })
            }
        }
    }
    running?.let { script ->
        ScriptRunSheet(script, onEdit = { running = null; editing = script }, onClose = { running = null })
    }
    editing?.let { script ->
        ScriptEditor(script, onSave = { app.scripts.save(it); editing = null },
            onDelete = { app.scripts.delete(it.id); editing = null }, onCancel = { editing = null })
    }
}

@Composable
private fun ScriptEditor(
    script: SavedScript,
    onSave: (SavedScript) -> Unit,
    onDelete: (SavedScript) -> Unit,
    onCancel: () -> Unit,
) {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val servers by app.fleet.deployments.collectAsState()
    var name by remember { mutableStateOf(script.name) }
    var body by remember { mutableStateOf(script.body) }
    var chosen by remember { mutableStateOf(script.deploymentIDs.toSet()) }
    val draft = script.copy(name = name.trim(), body = body, deploymentIDs = chosen.toList())
    val actions = buildList {
        add(AlertAction(stringResource(R.string.access_cancel), onSelect = onCancel))
        if (script.name.isNotEmpty()) {
            add(AlertAction(stringResource(R.string.scripts_delete), destructive = true, onSelect = { onDelete(script) }))
        }
        add(AlertAction(stringResource(R.string.port_forwarding_save), enabled = draft.isValid, preferred = true,
            onSelect = { onSave(draft) }))
    }
    FormSheet(
        title = stringResource(R.string.scripts_edit),
        onDismiss = onCancel,
        actions = actions,
        content = {
            AlertFields {
                OutlinedTextField(name, { name = it }, label = { Text(stringResource(R.string.scripts_name)) })
                OutlinedTextField(body, { body = it }, label = { Text(stringResource(R.string.scripts_edit)) }, minLines = 4)
            }
            Text(stringResource(R.string.scripts_servers_hint), color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(top = 8.dp))
            servers.forEach { server ->
                val on = server.id in chosen
                Text(
                    (if (on) "✓ " else "○ ") + server.name,
                    color = Gryonix.colors.label,
                    modifier = Modifier.fillMaxWidth().clickable { chosen = if (on) chosen - server.id else chosen + server.id }
                        .padding(vertical = 6.dp),
                )
            }
        },
    )
}
