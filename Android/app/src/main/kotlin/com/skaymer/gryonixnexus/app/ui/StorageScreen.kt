package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.app.storage.StorageAgentTasks
import androidx.compose.foundation.background
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
import com.skaymer.gryonixnexus.app.storage.StorageState
import com.skaymer.gryonixnexus.app.storage.StorageViewModel
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.AlertFields
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.catalog.storage.ArrayChange
import com.skaymer.gryonixnexus.catalog.storage.DiskJob
import com.skaymer.gryonixnexus.catalog.storage.RaidImportPlan
import com.skaymer.gryonixnexus.catalog.storage.RaidPlan
import com.skaymer.gryonixnexus.catalog.storage.RaidRepairPlan
import com.skaymer.gryonixnexus.catalog.storage.ServerDisk
import com.skaymer.gryonixnexus.catalog.storage.StorageArray
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

/** Arrays, their health, and repair when needed */
@Composable
fun StorageScreen(server: Deployment, host: SSHHostID) {
    val model = (LocalContext.current.applicationContext as GryonixApplication).storage
    val state by model.state.collectAsState()
    var repairing by remember { mutableStateOf<StorageArray?>(null) }
    var building by remember { mutableStateOf(false) }
    var checkingHealth by remember { mutableStateOf(false) }
    var managing by remember { mutableStateOf<StorageArray?>(null) }
    var inspecting by remember { mutableStateOf<ServerDisk?>(null) }
    val account = remember(server.id, host) { StorageAccount.of(server, host) }
    val target = StorageRunTarget(model, server, host, account)
    LaunchedEffect(server.id, host) { model.load(server, host) }
    LaunchedEffect(server.id, host, state.isBusy) { model.follow(server, host) }

    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item { ArraysSection(state, onManage = { managing = it }) { repairing = it } }
        if (state.running || state.stepFailure != null) item { StepSection(state) }
        state.hardware?.diskJob?.takeIf { it.isRecent() }?.let { job -> item { DiskJobSection(job) } }
        state.hardware?.takeIf { RaidPlan.candidates(it).size >= 2 }?.let {
            item {
                GroupedSection(footer = stringResource(R.string.storage_build_note)) {
                    ActionRow(
                        text = stringResource(R.string.storage_build_action),
                        onClick = { building = true },
                        showDivider = false,
                    )
                }
            }
        }
        if (state.hardware?.disks?.isNotEmpty() == true) {
            item {
                GroupedSection(footer = stringResource(R.string.health_note)) {
                    ActionRow(stringResource(R.string.health_check), onClick = { checkingHealth = true }, showDivider = false)
                }
            }
        }
        state.hardware?.let { hardware ->
            item {
                GroupedSection(header = stringResource(R.string.storage_disks), note = stringResource(R.string.storage_disks_footer)) {
                    hardware.disks.forEach { disk ->
                        ValueRow(
                            diskTitle(disk), null, onClick = { inspecting = disk }, subtitle = diskDetail(disk),
                            showDivider = disk != hardware.disks.last(),
                        )
                    }
                }
            }
        }
    }
    repairing?.let { array -> RepairDialog(model, state, server, host, array, account) { repairing = null } }
    if (building) StorageBuildSheet(model, state, server, host, account) { building = false }
    if (checkingHealth) DiskHealthDialog(model, state, server, host, account) { checkingHealth = false }
    managing?.let { array -> ArrayManageSheet(target, state, array) { managing = null } }
    inspecting?.let { disk -> DiskManageSheet(target, state, disk) { inspecting = null } }
}

@Composable
private fun StepSection(state: StorageState) {
    GroupedSection(footer = state.failureText()) {
        ValueRow(
            stringResource(if (state.running) R.string.storage_working else R.string.storage_step_failed),
            null, null, showDivider = false,
        )
    }
}

@Composable
private fun DiskJobSection(job: DiskJob) {
    GroupedSection(header = stringResource(R.string.storage_job_header), note = stringResource(R.string.storage_job_footer)) {
        ValueRow(jobTitle(job), jobOutcome(job), null, showDivider = job.lastLines.isNotEmpty())
        job.lastLines.forEachIndexed { index, line ->
            ValueRow(line, null, null, showDivider = index < job.lastLines.lastIndex)
        }
    }
}

@Composable
private fun ArraysSection(state: StorageState, onManage: (StorageArray) -> Unit, onRepair: (StorageArray) -> Unit) {
    GroupedSection(
        header = stringResource(R.string.storage_raid_arrays),
        footer = state.errorMessage ?: stringResource(R.string.storage_degraded_note),
    ) {
        if (state.arrays.isEmpty()) {
            ValueRow(
                stringResource(if (state.isLoading) R.string.storage_reading else R.string.storage_no_arrays),
                null, null, showDivider = false,
            )
        }
        state.arrays.forEach { array ->
            val managed = ArrayChange.manages(array)
            ValueRow(arrayTitle(array), null, onClick = if (managed) ({ onManage(array) }) else null, subtitle = arrayState(array))
            if (array.needsAttention && !array.repairsHere) {
                ValueRow(stringResource(R.string.storage_repair_elsewhere), null, null)
            } else if (array.needsAttention) {
                ActionRow(
                    text = stringResource(
                        if (array.state == StorageArray.State.Stopped) R.string.storage_bring_back_action
                        else R.string.storage_replace_action,
                    ),
                    onClick = { onRepair(array) },
                )
            }
        }
    }
}

@Composable
private fun RepairDialog(
    model: StorageViewModel,
    state: StorageState,
    server: Deployment,
    host: SSHHostID,
    array: StorageArray,
    account: StorageAccount,
    onClose: () -> Unit,
) {
    val word = stringResource(R.string.storage_erase_word)
    var sign by remember { mutableStateOf(account.sign) }
    var replacement by remember { mutableStateOf<String?>(null) }
    var typed by remember { mutableStateOf("") }
    val stopped = array.state == StorageArray.State.Stopped
    val spares = state.hardware?.let { RaidRepairPlan.candidates(it, array) }.orEmpty()
    val step = if (stopped) {
        StorageAgentTasks.importing(array)
    } else {
        spares.firstOrNull { it.path == replacement }?.takeIf { typed.trim().equals(word, ignoreCase = true) }
            ?.takeIf { array.kind != StorageArray.Kind.ZFS || array.failed.isNotEmpty() }
            ?.let { StorageAgentTasks.repair(array, it) }
    }
    IOSAlert(
        title = stringResource(if (stopped) R.string.storage_bring_back_title else R.string.storage_replace_title),
        message = state.failureText() ?: stringResource(R.string.storage_root_note),
        onDismiss = onClose,
        actions = listOf(
            AlertAction(stringResource(R.string.access_cancel), onSelect = onClose),
            AlertAction(
                stringResource(if (stopped) R.string.storage_bring_back else R.string.storage_replace),
                destructive = !stopped,
                enabled = step != null && !state.running,
                onSelect = {
                    step?.let { sign.run(model, server, host, it) }
                    onClose()
                },
            ),
        ),
    ) {
        AlertFields {
            if (!stopped) {
                spares.forEach { disk ->
                    ActionRow(
                        text = (if (disk.path == replacement) "✓ " else "") + disk.name + " · " + disk.model,
                        onClick = { replacement = disk.path },
                    )
                }
                FieldRow(label = word, value = typed, onValueChange = { typed = it })
            }
            StorageSignInRows(account, sign) { sign = it }
        }
    }
}

/** The step's failure, translated when the agent is too old */
@Composable
fun StorageState.failureText(): String? =
    if (outdatedAgent) stringResource(R.string.agent_outdated) else stepFailure
