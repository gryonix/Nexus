package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.app.storage.StorageAgentTasks
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.install.StorageStep
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.catalog.storage.FastStorageMove
import com.skaymer.gryonixnexus.catalog.storage.FastStoragePlan
import com.skaymer.gryonixnexus.catalog.storage.FastStorageRestore
import com.skaymer.gryonixnexus.catalog.storage.RaidPlan
import com.skaymer.gryonixnexus.catalog.storage.ServerDisk
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

private const val PROBE_DONE = "GRYONIXNEXUS_FAST_PROBE_DONE"

/** What the screen is waiting on */
private enum class CachePending { FIND, MIRROR, MOVE, RESTORE, CLEANUP }

private enum class CacheQuestion { MOVE, RESTORE, CLEANUP }

/** Moves databases and caches to a fast disk and back */
@Composable
fun CacheDiskScreen(server: Deployment, host: SSHHostID) {
    val model = (LocalContext.current.applicationContext as GryonixApplication).storage
    val state by model.state.collectAsState()
    val account = remember(server.id, host) { StorageAccount.of(server, host) }
    var sign by remember { mutableStateOf(account.sign) }
    var disk by remember { mutableStateOf<String?>(null) }
    var mirror by remember { mutableStateOf<String?>(null) }
    var projects by remember { mutableStateOf<List<FastStorageMove.Project>?>(null) }
    var bound by remember { mutableStateOf<Set<String>>(emptySet()) }
    var pending by remember { mutableStateOf<CachePending?>(null) }
    var asking by remember { mutableStateOf<CacheQuestion?>(null) }
    LaunchedEffect(server.id, host) { model.load(server, host) }
    val candidates = state.hardware?.let { FastStoragePlan.candidates(it) }.orEmpty()
    val chosen = candidates.firstOrNull { it.path == (disk ?: candidates.firstOrNull()?.path) }
    val partners = if (chosen?.isBlank == true) candidates.filter { it.isBlank && it != chosen } else emptyList()
    val (waiting, moved) = splitByCache(projects.orEmpty(), bound)

    fun run(kind: CachePending, step: StorageStep) {
        pending = kind
        sign.run(model, server, host, step)
    }
    fun find() = run(CachePending.FIND, probeStep())
    fun move(target: FastStoragePlan.Target) = run(CachePending.MOVE, StorageAgentTasks.cacheMove(FastStorageMove(target, waiting)))

    LaunchedEffect(state.running) {
        if (state.running) return@LaunchedEffect
        val finished = pending ?: return@LaunchedEffect
        pending = null
        when (finished) {
            CachePending.FIND -> state.lastOutput?.let {
                projects = FastStorageMove.projects(it)
                bound = FastStorageMove.bound(it)
            }
            CachePending.MIRROR -> if (state.stepFailure == null) {
                val pair = RaidPlan.cacheMirror(listOfNotNull(chosen, partners.firstOrNull { it.path == mirror }))
                move(FastStoragePlan.Target.Device(pair.device))
            }
            else -> if (state.stepFailure == null) find()
        }
    }

    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item { DiskChoice(candidates, chosen, partners, mirror, state.isLoading, { disk = it }, { mirror = it }) }
        item { GroupedSection { StorageSignInRows(account, sign) { sign = it } } }
        item {
            GroupedSection(footer = state.failureText()) {
                ActionRow(
                    text = stringResource(if (projects == null) R.string.cache_find else R.string.cache_read_again),
                    enabled = !state.running, showDivider = false, onClick = { find() },
                )
            }
        }
        projects?.let { list -> item { Moves(list, bound) } }
        item { CacheMoveActions(waiting.isNotEmpty() && chosen != null, moved.isNotEmpty(), state.running) { asking = it } }
    }

    fun answer(question: CacheQuestion) {
        when (question) {
            CacheQuestion.MOVE -> {
                val target = chosen ?: return
                val partner = partners.firstOrNull { it.path == mirror }
                if (partner != null) {
                    run(CachePending.MIRROR, StorageAgentTasks.raid(
                        RaidPlan.cacheMirror(listOf(target, partner)), StorageStep.Kind.MIRROR,
                    ))
                } else {
                    move(FastStoragePlan(target, emptyList()).target)
                }
            }
            CacheQuestion.RESTORE -> run(CachePending.RESTORE, StorageAgentTasks.cacheRestore(moved))
            CacheQuestion.CLEANUP -> run(CachePending.CLEANUP, StorageAgentTasks.cacheCleanup(bound.sorted()))
        }
    }
    asking?.let { CacheQuestionAlert(it, onConfirm = { asking = null; answer(it) }, onCancel = { asking = null }) }
}

/** Folders still to move, and projects already on the cache */
private fun splitByCache(
    projects: List<FastStorageMove.Project>,
    bound: Set<String>,
): Pair<List<FastStorageMove.Project>, List<FastStorageMove.Project>> {
    val waiting = projects.mapNotNull { p ->
        p.hotPaths.filter { it !in bound }.takeIf { it.isNotEmpty() }?.let { FastStorageMove.Project(p.directory, it) }
    }
    return waiting to projects.filter { p -> p.hotPaths.any { it in bound } }
}

/** Reads which folders sit on the cache disk */
private fun probeStep(): StorageStep = StorageAgentTasks.cacheProbe(
    "#!/bin/bash\n${FastStorageMove.PROBE_COMMAND}\necho $PROBE_DONE\n", PROBE_DONE,
)

@Composable
private fun CacheMoveActions(canMove: Boolean, hasMoved: Boolean, running: Boolean, onAsk: (CacheQuestion) -> Unit) {
    Column(verticalArrangement = GroupedSpacing) {
        if (canMove) {
            GroupedSection {
                ActionRow(stringResource(R.string.cache_move), onClick = { onAsk(CacheQuestion.MOVE) },
                    enabled = !running, showDivider = false)
            }
        }
        if (hasMoved) {
            GroupedSection(footer = stringResource(R.string.cache_old_copies_note)) {
                ActionRow(stringResource(R.string.cache_restore), onClick = { onAsk(CacheQuestion.RESTORE) },
                    enabled = !running)
                ActionRow(stringResource(R.string.cache_cleanup), onClick = { onAsk(CacheQuestion.CLEANUP) },
                    enabled = !running, danger = true, showDivider = false)
            }
        }
    }
}

@Composable
private fun CacheQuestionAlert(question: CacheQuestion, onConfirm: () -> Unit, onCancel: () -> Unit) {
    ConfirmAlert(
        title = stringResource(when (question) {
            CacheQuestion.MOVE -> R.string.cache_move_question
            CacheQuestion.RESTORE -> R.string.cache_restore_question
            CacheQuestion.CLEANUP -> R.string.cache_cleanup_question
        }),
        message = stringResource(
            if (question == CacheQuestion.CLEANUP) R.string.cache_cleanup_message else R.string.cache_move_message,
        ),
        confirm = stringResource(when (question) {
            CacheQuestion.MOVE -> R.string.cache_move_confirm
            CacheQuestion.RESTORE -> R.string.cache_restore_confirm
            CacheQuestion.CLEANUP -> R.string.cache_cleanup_confirm
        }),
        destructive = question == CacheQuestion.CLEANUP,
        onConfirm = onConfirm,
        onCancel = onCancel,
    )
}

@Composable
private fun DiskChoice(
    candidates: List<ServerDisk>,
    chosen: ServerDisk?,
    partners: List<ServerDisk>,
    mirror: String?,
    loading: Boolean,
    onPick: (String) -> Unit,
    onMirror: (String?) -> Unit,
) {
    GroupedSection(
        header = stringResource(R.string.cache_disk_title),
        footer = stringResource(R.string.cache_note),
    ) {
        if (candidates.isEmpty()) {
            ValueRow(
                stringResource(if (loading) R.string.storage_reading else R.string.cache_no_candidate),
                null, null, showDivider = false,
            )
        }
        candidates.forEach { disk ->
            ActionRow(
                text = (if (disk == chosen) "✓ " else "") + label(disk),
                onClick = { onPick(disk.path) },
                showDivider = disk != candidates.last() || partners.isNotEmpty(),
            )
        }
    }
    if (partners.isNotEmpty()) {
        GroupedSection(header = stringResource(R.string.storage_mirror_onto)) {
            ActionRow(text = (if (mirror == null) "✓ " else "") + stringResource(R.string.storage_none), onClick = { onMirror(null) })
            partners.forEach { disk ->
                ActionRow(
                    text = (if (disk.path == mirror) "✓ " else "") + label(disk),
                    onClick = { onMirror(disk.path) },
                    showDivider = disk != partners.last(),
                )
            }
        }
    }
}

private fun label(disk: ServerDisk) = listOf(disk.name, disk.model).filter { it.isNotEmpty() }.joinToString(" · ")

@Composable
private fun Moves(projects: List<FastStorageMove.Project>, bound: Set<String>) {
    GroupedSection(header = stringResource(R.string.cache_moves)) {
        if (projects.isEmpty()) {
            ValueRow(stringResource(R.string.cache_nothing), null, null, showDivider = false)
        }
        projects.forEach { project ->
            ValueRow(
                project.directory.substringAfterLast('/'), null, null,
                subtitle = project.hotPaths.joinToString("\n") { (if (it in bound) "⚡ " else "") + it },
                showDivider = project != projects.last(),
            )
        }
    }
}

/** Disks, RAID and the cache disk, on the General tab */
@Composable
fun StorageCard(deployment: Deployment, onOpenStorage: (SSHHostID) -> Unit, onOpenCache: (SSHHostID) -> Unit) {
    val overview = (LocalContext.current.applicationContext as GryonixApplication).storageOverview
    val hardware by overview.hardware.collectAsState()
    LaunchedEffect(deployment.id) { overview.load(deployment) }
    val raidHosts = deployment.nodes.filter { node -> hardware[node.sshHost]?.let(StorageOverviewRules::manages) == true }
    val cacheHosts = deployment.nodes.filter { node -> hardware[node.sshHost]?.let(StorageOverviewRules::offersCache) == true }
    if (raidHosts.isEmpty() && cacheHosts.isEmpty()) return
    val several = deployment.nodes.size > 1
    val rows = raidHosts.map { node -> Triple(node, true, node.name.ifEmpty { node.endpoint.host }) } +
        cacheHosts.map { node -> Triple(node, false, node.name.ifEmpty { node.endpoint.host }) }
    GroupedSection(header = stringResource(R.string.storage_section)) {
        rows.forEachIndexed { index, (node, raid, name) ->
            val base = stringResource(if (raid) R.string.storage_disks_and_raid else R.string.cache_disk_title)
            ValueRow(
                title = if (several) "$base — $name" else base,
                value = null,
                onClick = { if (raid) onOpenStorage(node.sshHost) else onOpenCache(node.sshHost) },
                showDivider = index != rows.lastIndex,
            )
        }
    }
}

private typealias StorageOverviewRules = com.skaymer.gryonixnexus.app.storage.StorageOverview.Companion
