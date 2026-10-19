package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ai.ModelKeysViewModel
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.catalog.LLMProvider
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** The row that opens the keys */
@Composable
fun ModelKeysCard(onOpen: () -> Unit, showDivider: Boolean = true) {
    ValueRow(
        title = stringResource(R.string.model_keys),
        value = null,
        onClick = onOpen,
        showDivider = showDivider,
        leading = {
            Icon(Icons.Filled.VpnKey, contentDescription = null, modifier = Modifier.size(22.dp))
        },
    )
}

@Composable
fun ModelKeysDialog(
    deployment: Deployment,
    keys: ModelKeysViewModel,
    onClose: () -> Unit,
) {
    val state by keys.state.collectAsState()
    val typed = remember(deployment.id) { mutableStateMapOf<String, String>() }

    LaunchedEffect(deployment.id) { keys.load(deployment) }

    IOSSheet(
        title = stringResource(R.string.model_keys_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_done),
        action = SheetAction(
            title = stringResource(R.string.model_keys_save),
            enabled = !state.isSaving && !state.isLoading && typed.values.any { it.isNotBlank() },
            onSelect = {
                keys.save(deployment, typed.toMap())
                typed.clear()
            },
        ),
    ) {
        if (state.isLoading) {
            Row(
                Modifier.padding(horizontal = Metrics.listInset + 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CircularProgressIndicator(
                    Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = Gryonix.colors.tertiaryLabel,
                )
                Text(
                    stringResource(R.string.model_keys_loading),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
        } else {
            GroupedSection(
                header = stringResource(R.string.model_keys_header),
                note = stringResource(R.string.model_keys_footer),
            ) {
                LLMProvider.ALL.forEach { provider ->
                    FieldRow(
                        label = provider.displayName,
                        value = typed[provider.id].orEmpty(),
                        onValueChange = { typed[provider.id] = it },
                        visualTransformation = PasswordVisualTransformation(),
                        showDivider = true,
                    )
                    GroupedRow(showDivider = provider != LLMProvider.ALL.last()) {
                        Text(
                            if (provider.id in state.stored) {
                                stringResource(R.string.model_keys_stored)
                            } else {
                                provider.consoleURL
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = Gryonix.colors.secondaryLabel,
                        )
                    }
                }
            }
            GroupedSection(
                footer = stringResource(R.string.model_keys_encryption_footer),
            ) {
                GroupedRow(showDivider = false) {
                    Text(
                        when {
                            state.errorMessage == ModelKeysViewModel.NO_AGENT ->
                                stringResource(R.string.model_keys_no_agent)
                            state.errorMessage != null ->
                                state.errorMessage.orEmpty()
                            state.saved -> stringResource(R.string.model_keys_saved)
                            else -> stringResource(R.string.model_keys_hint)
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        color = Gryonix.colors.secondaryLabel,
                    )
                }
            }
        }
    }
}
