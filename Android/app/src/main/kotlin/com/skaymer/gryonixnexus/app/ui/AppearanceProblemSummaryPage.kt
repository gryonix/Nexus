package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.servercontrol.ServerProblem

/** Appearance → Problem summary: the tiles above the servers */
@Composable
internal fun AppearanceProblemSummaryPage(store: SettingsStore) {
    val revision by store.revision.collectAsState()
    val shown = remember(revision) { store.boolean(PROBLEM_SUMMARY_KEY) ?: true }
    val hiddenRaw = remember(revision) { store.string(PROBLEM_SUMMARY_HIDDEN_KEY) }
    val tiles = remember(hiddenRaw) { visibleProblemTiles(hiddenRaw) }
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item {
            GroupedSection(footer = stringResource(R.string.problem_summary_footer)) {
                ToggleRow(
                    title = stringResource(R.string.problem_summary_show),
                    checked = shown,
                    onCheckedChange = { store.setBoolean(PROBLEM_SUMMARY_KEY, it) },
                    showDivider = false,
                )
            }
        }
        if (shown) {
            item {
                GroupedSection(header = stringResource(R.string.problem_summary_tiles)) {
                    ServerProblem.entries.forEach { problem ->
                        ToggleRow(
                            title = stringResource(title(problem)),
                            checked = problem in tiles,
                            onCheckedChange = {
                                store.setString(PROBLEM_SUMMARY_HIDDEN_KEY, problemTilesHiddenRaw(hiddenRaw, problem, it))
                            },
                            showDivider = problem != ServerProblem.entries.last(),
                        )
                    }
                }
            }
        }
    }
}

/** The value shown on the Appearance row */
@Composable
internal fun problemSummaryValue(store: SettingsStore, revision: Long): String {
    val shown = remember(revision) { store.boolean(PROBLEM_SUMMARY_KEY) ?: true }
    if (!shown) return stringResource(R.string.widget_off)
    val count = remember(revision) { visibleProblemTiles(store.string(PROBLEM_SUMMARY_HIDDEN_KEY)).size }
    return "$count/${ServerProblem.entries.size}"
}
