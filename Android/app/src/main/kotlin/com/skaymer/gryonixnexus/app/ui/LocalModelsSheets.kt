package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ai.LocalModelsViewModel
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** The row that opens the models */
@Composable
fun LocalModelsCard(onOpen: () -> Unit, showDivider: Boolean = true) {
    ValueRow(
        title = stringResource(R.string.local_models),
        value = null,
        onClick = onOpen,
        showDivider = showDivider,
        leading = {
            Icon(Icons.Filled.Inventory2, contentDescription = null, modifier = Modifier.size(22.dp))
        },
    )
}

@Composable
fun LocalModelsDialog(
    deployment: Deployment,
    models: LocalModelsViewModel,
    onClose: () -> Unit,
) {
    val state by models.state.collectAsState()
    var wanted by remember(deployment.id) { mutableStateOf("") }

    LaunchedEffect(deployment.id) { models.load(deployment) }

    IOSSheet(
        title = stringResource(R.string.local_models_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_done),
        action = SheetAction(
            title = stringResource(R.string.local_models_fetch),
            enabled = state.enginePresent && state.pull == null && wanted.isNotBlank(),
            onSelect = {
                models.fetch(deployment, wanted)
                wanted = ""
            },
        ),
    ) {
        when {
            state.isLoading -> LoadingRow(stringResource(R.string.local_models_loading))
            state.errorMessage == LocalModelsViewModel.NO_AGENT ->
                GroupedSection { GroupedRow(showDivider = false) { Caption(stringResource(R.string.local_models_no_agent)) } }
            !state.enginePresent -> GroupedSection(
                footer = stringResource(R.string.local_models_no_engine_footer),
            ) {
                GroupedRow(showDivider = false) { Caption(stringResource(R.string.local_models_no_engine)) }
            }
            else -> {
                GroupedSection(
                    header = stringResource(R.string.local_models_header),
                    footer = state.path.takeIf { it.isNotEmpty() },
                ) {
                    if (state.models.isEmpty()) {
                        GroupedRow(showDivider = false) {
                            Caption(stringResource(R.string.local_models_empty))
                        }
                    } else {
                        state.models.forEachIndexed { index, model ->
                            GroupedRow(showDivider = index != state.models.lastIndex) {
                                Row(
                                    Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Column(Modifier.weight(1f)) {
                                        Text(
                                            model.name,
                                            style = MaterialTheme.typography.bodyMedium,
                                            color = Gryonix.colors.label,
                                        )
                                        Caption(
                                            listOf(
                                                LocalModelsViewModel.human(model.size_bytes),
                                                model.parameter_size,
                                                model.quantization,
                                            ).filter { it.isNotEmpty() }.joinToString(" · ")
                                        )
                                    }
                                    if (state.removing == model.name) {
                                        CircularProgressIndicator(
                                            Modifier.size(16.dp),
                                            strokeWidth = 2.dp,
                                            color = Gryonix.colors.tertiaryLabel,
                                        )
                                    } else {
                                        IconButton(
                                            onClick = { models.remove(deployment, model.name) },
                                            enabled = state.pull == null,
                                        ) {
                                            Icon(
                                                Icons.Filled.Delete,
                                                contentDescription = stringResource(R.string.delete_server_confirm),
                                                modifier = Modifier.size(20.dp),
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                GroupedSection(
                    header = stringResource(R.string.local_models_fetch_header),
                    note = stringResource(R.string.local_models_fetch_footer),
                ) {
                    val pull = state.pull
                    if (pull == null) {
                        FieldRow(
                            label = stringResource(R.string.local_models_name),
                            value = wanted,
                            onValueChange = { wanted = it },
                            placeholder = "llama3.2:3b",
                            showDivider = true,
                        )
                    } else {
                        GroupedRow(showDivider = true) {
                            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                val fraction = pull.fraction
                                if (fraction != null) {
                                    LinearProgressIndicator(
                                        progress = { fraction },
                                        modifier = Modifier.fillMaxWidth(),
                                    )
                                    Caption(
                                        LocalModelsViewModel.human(pull.completed) + " / " +
                                            LocalModelsViewModel.human(pull.total)
                                    )
                                } else {
                                    LinearProgressIndicator(Modifier.fillMaxWidth())
                                }
                                if (pull.text.isNotEmpty()) Caption(pull.text)
                                if (pull.jobID.isNotEmpty()) {
                                    if (pull.stopping) {
                                        Caption(stringResource(R.string.local_models_stopping))
                                    } else {
                                        TextButton(
                                            onClick = { models.stop(deployment) },
                                            contentPadding = PaddingValues(0.dp),
                                        ) {
                                            Text(
                                                stringResource(R.string.local_models_stop),
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.error,
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    GroupedRow(showDivider = false) {
                        Caption(
                            state.errorMessage
                                ?: stringResource(
                                    R.string.local_models_free,
                                    LocalModelsViewModel.human(state.freeBytes),
                                    LocalModelsViewModel.human(state.totalBytes),
                                )
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun LoadingRow(text: String) {
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
        Caption(text)
    }
}

@Composable
private fun Caption(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = Gryonix.colors.secondaryLabel,
    )
}
