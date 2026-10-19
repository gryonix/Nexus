package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.agentcontrol.PreRestoreCopy
import com.skaymer.gryonixnexus.app.servers.MetricsFormat
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** Old restore copies, each with a delete button */
@Composable
fun OldCopiesSection(copies: List<PreRestoreCopy>, onDelete: (PreRestoreCopy) -> Unit) {
    if (copies.isEmpty()) return
    val colors = Gryonix.colors
    GroupedSection(header = stringResource(R.string.backups_old_copies)) {
        copies.forEach { copy ->
            GroupedRow(
                showDivider = copy != copies.last(),
                trailing = {
                    IconButton(onClick = { onDelete(copy) }, modifier = Modifier.size(28.dp)) {
                        Icon(
                            Icons.Filled.Delete,
                            contentDescription = stringResource(R.string.backups_delete),
                            tint = colors.danger,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                },
            ) {
                RowLabel(copy.name, "${sizeText(copy)} · ${dateText(copy)}")
            }
        }
    }
}

private fun sizeText(copy: PreRestoreCopy): String =
    if (copy.sizeKnown) MetricsFormat.bytes(copy.sizeBytes) else "—"

private fun dateText(copy: PreRestoreCopy): String =
    DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
        .withZone(ZoneId.systemDefault())
        .format(Instant.ofEpochSecond(copy.movedAsideSeconds))
