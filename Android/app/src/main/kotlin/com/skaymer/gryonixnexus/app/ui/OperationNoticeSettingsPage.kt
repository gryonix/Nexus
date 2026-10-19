package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationDisplay
import com.skaymer.gryonixnexus.app.notify.OperationKind
import com.skaymer.gryonixnexus.app.notify.OperationNoticeCheck
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow

/** Which running operations show as notifications */
@Composable
fun OperationNoticeSettingsPage(store: SettingsStore) {
    val context = LocalContext.current
    val revision by store.revision.collectAsState()
    val display = remember(revision) { OperationDisplay.load(store) }
    val change: (OperationDisplay) -> Unit = { it.save(store) }
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item {
            GroupedSection(
                header = stringResource(R.string.operations_header),
                note = stringResource(R.string.operations_footer),
            ) {
                OperationNoticeRows(display, change)
            }
        }
        if (OperationNoticeCheck.isOffered(context)) item { OperationNoticeCheckSection() }
    }
}

@Composable
private fun OperationNoticeCheckSection() {
    val context = LocalContext.current
    GroupedSection(note = stringResource(R.string.operations_test_footer)) {
        ActionRow(
            stringResource(R.string.operations_test),
            { OperationNoticeCheck.run(context.applicationContext) },
            showDivider = false,
        )
    }
}

@Composable
private fun OperationNoticeRows(display: OperationDisplay, change: (OperationDisplay) -> Unit) {
    ToggleRow(
        stringResource(R.string.operations_show), display.enabled,
        { change(display.copy(enabled = it)) }, showDivider = display.enabled,
    )
    if (!display.enabled) return
    val kinds = OperationKind.entries
    kinds.forEach { kind ->
        ToggleRow(
            stringResource(kind.titleRes), kind !in display.hidden,
            { change(display.withKind(kind, it)) }, showDivider = kind != kinds.last(),
        )
    }
}

private val OperationKind.titleRes: Int
    get() = when (this) {
        OperationKind.INSTALL -> R.string.operations_kind_install
        OperationKind.UPDATE -> R.string.operations_kind_update
        OperationKind.BACKUP -> R.string.operations_kind_backup
        OperationKind.RESTORE -> R.string.operations_kind_restore
        OperationKind.MOVE -> R.string.operations_kind_move
        OperationKind.REMOVAL -> R.string.operations_kind_removal
        OperationKind.OTHER -> R.string.operations_kind_other
    }
