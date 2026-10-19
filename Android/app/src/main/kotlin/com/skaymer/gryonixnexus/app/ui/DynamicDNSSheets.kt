package com.skaymer.gryonixnexus.app.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.PasswordVisualTransformation
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.app.dns.DynamicDNSViewModel
import com.skaymer.gryonixnexus.servercontrol.Deployment

@Composable
fun DynamicDNSCard(onOpen: () -> Unit, showDivider: Boolean = true) {
    ValueRow(
        title = stringResource(R.string.ddns_title),
        value = null,
        onClick = onOpen,
        showDivider = showDivider,
    )
}

/** Dynamic DNS for one server */
@Composable
fun DynamicDNSDialog(
    deployment: Deployment,
    dns: DynamicDNSViewModel,
    onClose: () -> Unit,
) {
    val screen by dns.state.collectAsState()
    var zone by remember(deployment.id) { mutableStateOf("") }
    var names by remember(deployment.id) { mutableStateOf("") }
    var token by remember(deployment.id) { mutableStateOf("") }

    LaunchedEffect(deployment.id) { dns.load(deployment) }
    LaunchedEffect(screen.state) {
        val state = screen.state ?: return@LaunchedEffect
        if (zone.isEmpty()) zone = state.zone
        if (names.isEmpty()) names = state.names.joinToString("\n")
    }

    val entered = DynamicDNSViewModel.names(names)
    val hasStoredToken = screen.state?.has_token == true

    IOSSheet(
        title = stringResource(R.string.ddns_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_cancel),
        action = SheetAction(
            title = stringResource(R.string.containers_save),
            enabled = !screen.isWorking &&
                DynamicDNSViewModel.canSave(zone, entered, token, hasStoredToken),
            onSelect = {
                dns.save(deployment, zone.trim(), entered, token)
                onClose()
            },
        ),
    ) {
        GroupedSection(footer = stringResource(R.string.ddns_zone_rule)) {
            FieldRow(
                label = stringResource(R.string.ddns_zone),
                value = zone,
                onValueChange = { zone = it },
                showDivider = false,
            )
        }
        GroupedSection(footer = stringResource(R.string.ddns_names_rule)) {
            FieldRow(
                label = stringResource(R.string.ddns_names),
                value = names,
                onValueChange = { names = it },
                singleLine = false,
                showDivider = false,
            )
        }
        GroupedSection(
            footer = screen.errorMessage ?: stringResource(
                if (hasStoredToken) R.string.ddns_token_stored else R.string.ddns_token_rule
            ),
        ) {
            FieldRow(
                label = stringResource(R.string.ddns_token),
                value = token,
                onValueChange = { token = it },
                visualTransformation = PasswordVisualTransformation(),
                showDivider = false,
            )
        }

        val recent = screen.state?.recent.orEmpty()
        if (recent.isNotEmpty()) {
            GroupedSection(header = stringResource(R.string.ddns_recent)) {
                val newestFirst = recent.reversed()
                newestFirst.forEach { line ->
                    GroupedRow(showDivider = line != newestFirst.last()) {
                        Text(
                            line,
                            style = MaterialTheme.typography.labelSmall,
                            fontFamily = FontFamily.Monospace,
                            color = Gryonix.colors.secondaryLabel,
                        )
                    }
                }
            }
        }

        if (screen.state?.enabled == true) {
            GroupedSection {
                ActionRow(
                    text = stringResource(R.string.ddns_stop),
                    onClick = {
                        dns.save(deployment, zone.trim(), emptyList(), "")
                        onClose()
                    },
                    danger = true,
                    showDivider = false,
                )
            }
        }
    }
}
