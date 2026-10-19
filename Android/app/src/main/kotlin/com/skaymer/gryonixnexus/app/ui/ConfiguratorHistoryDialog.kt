package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.configurator.ConfiguratorHistoryEntry
import java.text.DateFormat
import java.util.Date

@Composable
fun ConfiguratorHistoryDialog(
    entries: List<ConfiguratorHistoryEntry>,
    onRestore: (ConfiguratorHistoryEntry) -> Unit,
    onDelete: (Set<String>) -> Unit,
    onClose: () -> Unit,
) {
    var shown by remember { mutableStateOf(entries) }

    IOSSheet(
        title = stringResource(R.string.configurator_history_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_done),
    ) {
        if (shown.isEmpty()) {
            Text(
                stringResource(R.string.configurator_history_empty),
                style = MaterialTheme.typography.bodyMedium,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
            )
        } else {
            shown.forEach { entry ->
                HistoryRow(
                    entry = entry,
                    onRestore = { onRestore(entry); onClose() },
                    onDelete = {
                        onDelete(setOf(entry.id))
                        shown = shown.filterNot { it.id == entry.id }
                    },
                )
            }
        }
    }
}

@Composable
private fun HistoryRow(
    entry: ConfiguratorHistoryEntry,
    onRestore: () -> Unit,
    onDelete: () -> Unit,
) {
    GroupedSection(
        header = // A configuration with no domain yet is still worth keeping —
            entry.domain.ifEmpty { stringResource(R.string.configurator_history_no_domain) },
    ) {
        GroupedRow {
            RowLabel(
                pluralStringResource(
                    R.plurals.configurator_history_services,
                    entry.services.size,
                    entry.services.size,
                ),
                DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
                    .format(Date(entry.savedAt)),
            )
        }
        ActionRow(
            text = stringResource(R.string.configurator_history_restore),
            onClick = onRestore,
        )
        ActionRow(
            text = stringResource(R.string.configurator_history_delete),
            onClick = onDelete,
            danger = true,
            showDivider = false,
        )
    }
}
