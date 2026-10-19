package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.terminal.ShellUserViewModel
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ShellUserCommand

@Composable
fun CreateShellUserSheet(
    deployment: Deployment,
    model: ShellUserViewModel,
    onClose: () -> Unit,
) {
    val state by model.state.collectAsState()
    var name by rememberSaveable { mutableStateOf("") }
    var withSudo by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(deployment.id) { model.reset() }

    val valid = ShellUserCommand.isValidName(name)

    IOSSheet(
        title = stringResource(R.string.shell_user_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.close),
    ) {
        GroupedSection(
            footer = if (name.isNotEmpty() && !valid) {
                stringResource(R.string.shell_user_name_invalid)
            } else {
                stringResource(R.string.shell_user_hint)
            },
        ) {
            FieldRow(
                label = stringResource(R.string.shell_user_name),
                value = name,
                onValueChange = { name = it },
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
            )
            ToggleRow(
                title = stringResource(R.string.shell_user_sudo),
                checked = withSudo,
                onCheckedChange = { withSudo = it },
                showDivider = false,
            )
        }

        GroupedSection(
            header = stringResource(R.string.shell_user_how_header),
            note = stringResource(R.string.shell_user_how_note),
        ) {
            ActionRow(
                text = if (state.busy) {
                    stringResource(R.string.shell_user_creating)
                } else {
                    stringResource(R.string.shell_user_create)
                },
                onClick = { model.create(deployment, name, withSudo) },
                enabled = !state.busy && valid,
                showDivider = false,
            )
        }

        state.created?.let { account ->
            Column(Modifier.fillMaxWidth().padding(horizontal = Metrics.listInset + 4.dp)) {
                Text(
                    stringResource(R.string.shell_user_created, account),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.success,
                )
            }
        }
        state.failure?.let { message ->
            Column(Modifier.fillMaxWidth().padding(horizontal = Metrics.listInset + 4.dp)) {
                Text(
                    message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.danger,
                )
            }
        }
    }
}
