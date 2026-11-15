package com.skaymer.gryonixnexus.app.ui

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.FleetMetrics
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.widgets.FleetSnapshotStore
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ServerHealthFacts
import com.skaymer.gryonixnexus.servercontrol.ServerProblem

/** Settings key for showing the tiles */
const val PROBLEM_SUMMARY_KEY = "servers.problemSummary"

/** Settings key for the tiles switched off */
const val PROBLEM_SUMMARY_HIDDEN_KEY = "servers.problemSummary.hidden"

/** Tiles switched on, in enum order */
fun visibleProblemTiles(hiddenRaw: String?): List<ServerProblem> {
    val hidden = hiddenRaw.orEmpty().split(",").toSet()
    return ServerProblem.entries.filter { it.name !in hidden }
}

/** The stored value with one tile switched */
fun problemTilesHiddenRaw(raw: String?, problem: ServerProblem, shown: Boolean): String {
    val hidden = raw.orEmpty().split(",").filter { it.isNotEmpty() }.toMutableSet()
    if (shown) hidden.remove(problem.name) else hidden.add(problem.name)
    return ServerProblem.entries.map { it.name }.filter { it in hidden }.joinToString(",")
}

/** Counts of servers by problem; a tap filters the list */
@Composable
fun ServerProblemCards(
    counts: Map<ServerProblem, Int>,
    tiles: List<ServerProblem>,
    selection: ServerProblem?,
    onSelect: (ServerProblem?) -> Unit,
) {
    if (tiles.isEmpty()) return
    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min).padding(bottom = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        tiles.forEach { problem ->
            val count = counts[problem] ?: 0
            val chosen = selection == problem
            Column(
                Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .clip(RoundedCornerShape(12.dp))
                    .background(if (chosen) Gryonix.colors.accent.copy(alpha = 0.25f) else Gryonix.colors.cardBackground)
                    .clickable(enabled = count > 0 || chosen) { onSelect(if (chosen) null else problem) }
                    .padding(10.dp),
            ) {
                Text(count.toString(), style = MaterialTheme.typography.titleLarge,
                    color = if (count > 0) Gryonix.colors.label else Gryonix.colors.secondaryLabel)
                Text(stringResource(title(problem)), style = MaterialTheme.typography.labelSmall,
                    color = Gryonix.colors.secondaryLabel, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

internal fun title(problem: ServerProblem): Int = when (problem) {
    ServerProblem.UNREACHABLE -> R.string.problem_unreachable
    ServerProblem.DISK_ALMOST_FULL -> R.string.problem_disk_full
    ServerProblem.SERVICE_DOWN -> R.string.problem_service_down
    ServerProblem.UPDATES_PENDING -> R.string.problem_updates_pending
}

/** What each server's readings say about its health */
internal fun healthFacts(
    context: Context,
    deployments: List<Deployment>,
    metrics: FleetMetrics,
    offline: Set<String>,
): List<ServerHealthFacts> {
    val stored = FleetSnapshotStore(context).read()?.servers.orEmpty().associateBy { it.id }
    return deployments.map { deployment ->
        val known = stored[deployment.id]
        ServerHealthFacts(
            id = deployment.id,
            unreachable = deployment.id in offline,
            diskFraction = metrics.diskFraction(deployment.id) ?: known?.metrics?.diskPercent?.div(100),
            servicesDown = known?.services?.needingAttention,
            updatesPending = known?.updates?.waiting,
        )
    }
}
