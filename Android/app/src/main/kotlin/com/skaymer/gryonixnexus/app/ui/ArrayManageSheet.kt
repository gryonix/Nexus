package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.storage.StorageAgentTasks
import com.skaymer.gryonixnexus.app.storage.StorageState
import com.skaymer.gryonixnexus.app.storage.StorageViewModel
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.catalog.storage.ArrayChange
import com.skaymer.gryonixnexus.catalog.storage.RaidPlan
import com.skaymer.gryonixnexus.catalog.storage.ServerDisk
import com.skaymer.gryonixnexus.catalog.storage.ServerHardware
import com.skaymer.gryonixnexus.catalog.storage.StorageArray
import com.skaymer.gryonixnexus.catalog.storage.preview
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

/** Where a change runs, and as whom */
internal data class StorageRunTarget(
    val model: StorageViewModel,
    val server: Deployment,
    val host: SSHHostID,
    val account: StorageAccount,
)

/** One array's disks, then the change picked for it */
@Composable
internal fun ArrayManageSheet(target: StorageRunTarget, state: StorageState, array: StorageArray, onClose: () -> Unit) {
    var action by remember { mutableStateOf<ArrayChange.Action?>(null) }
    val picked = action
    if (picked == null) ArrayActionsSheet(state, array, onPick = { action = it }, onClose = onClose)
    else ArrayChangeSheet(target, state, array, picked, onClose)
}

@Composable
private fun ArrayActionsSheet(
    state: StorageState,
    array: StorageArray,
    onPick: (ArrayChange.Action) -> Unit,
    onClose: () -> Unit,
) {
    val hardware = state.hardware
    val actions = hardware?.let { ArrayChange.actions(array, it) }.orEmpty()
    IOSSheet(title = array.name, onClose = onClose, closeLabel = stringResource(R.string.access_cancel)) {
        GroupedSection {
            ValueRow(arrayTitle(array), null, null, subtitle = arrayState(array))
            (array.members + array.spares).forEach { ValueRow(memberTitle(it, hardware), null, null) }
        }
        val footer = when {
            actions.isEmpty() -> stringResource(R.string.storage_manage_none)
            hardware?.let { RaidPlan.candidates(it) }.isNullOrEmpty() -> stringResource(R.string.storage_manage_need_disk)
            else -> null
        }
        GroupedSection(footer = footer) {
            actions.forEach { ActionRow(changeTitle(it), onClick = { onPick(it) }, danger = it == ArrayChange.Action.DELETE) }
        }
    }
}

/** The member, new disks and level the change needs */
private data class ChangePicks(
    val member: String? = null,
    val first: String? = null,
    val second: String? = null,
    val level: RaidPlan.Level? = null,
    val typed: String = "",
)

@Composable
private fun ArrayChangeSheet(
    target: StorageRunTarget,
    state: StorageState,
    array: StorageArray,
    action: ArrayChange.Action,
    onClose: () -> Unit,
) {
    val hardware = state.hardware ?: return
    var picks by remember { mutableStateOf(ChangePicks()) }
    var sign by remember { mutableStateOf(target.account.sign) }
    val free = RaidPlan.candidates(hardware)
    val chosen = listOfNotNull(picks.first, picks.second).mapNotNull { path -> free.firstOrNull { it.path == path } }
    val change = ArrayChange(action, array, picks.member, chosen.take(action.newDisks(array)), picks.level)
    val word = stringResource(R.string.storage_erase_word)
    val confirmed = when {
        action == ArrayChange.Action.DELETE -> picks.typed.trim() == array.name
        change.disks.isEmpty() -> true
        else -> picks.typed.trim().equals(word, ignoreCase = true)
    }
    val step = if (change.isReady && confirmed) StorageAgentTasks.change(change, hardware) else null
    val danger = action == ArrayChange.Action.DELETE || change.disks.isNotEmpty()
    IOSSheet(
        title = changeTitle(action),
        onClose = onClose,
        closeLabel = stringResource(R.string.access_cancel),
        action = SheetAction(
            title = stringResource(if (action == ArrayChange.Action.DELETE) R.string.storage_delete else R.string.storage_start),
            enabled = step != null && !state.running,
            destructive = danger,
            onSelect = {
                step?.let { sign.run(target.model, target.server, target.host, it) }
                onClose()
            },
        ),
    ) {
        GroupedSection(footer = changeExplanation(action)) {
            ValueRow(arrayTitle(array), null, null, subtitle = arrayState(array), showDivider = false)
        }
        ChangeChoices(array, action, free, hardware, picks) { picks = it }
        if (change.isReady) ChangePreview(change, hardware)
        ChangeConfirm(action, array.name, change.disks.isNotEmpty(), word, picks) { picks = it }
        GroupedSection(header = stringResource(R.string.storage_sign_in)) {
            StorageSignInRows(target.account, sign) { sign = it }
        }
    }
}

@Composable
private fun ChangeChoices(
    array: StorageArray,
    action: ArrayChange.Action,
    free: List<ServerDisk>,
    hardware: ServerHardware,
    picks: ChangePicks,
    update: (ChangePicks) -> Unit,
) {
    val disks = action.newDisks(array)
    if (!action.takesMember && disks == 0 && action != ArrayChange.Action.CHANGE_LEVEL) return
    val none = stringResource(R.string.storage_none)
    GroupedSection {
        if (action.takesMember) {
            ChoiceRow(
                title = stringResource(R.string.storage_change_disk),
                value = picks.member?.let { memberTitle(it, hardware) } ?: none,
                options = array.members.map { path -> memberTitle(path, hardware) to { update(picks.copy(member = path)) } },
            )
        }
        if (action == ArrayChange.Action.CHANGE_LEVEL) {
            ChoiceRow(
                title = stringResource(R.string.storage_change_new_level),
                value = picks.level?.let { levelTitle(it) } ?: none,
                options = ArrayChange.levels(array).map { level -> levelTitle(level) to { update(picks.copy(level = level)) } },
            )
        }
        if (disks > 0) {
            ChoiceRow(
                title = stringResource(R.string.storage_change_new_disk),
                value = free.firstOrNull { it.path == picks.first }?.let { diskTitle(it) } ?: none,
                options = free.filter { it.path != picks.second }.map { disk -> diskTitle(disk) to { update(picks.copy(first = disk.path)) } },
                showDivider = disks > 1,
            )
        }
        if (disks > 1) {
            ChoiceRow(
                title = stringResource(R.string.storage_change_second_disk),
                value = free.firstOrNull { it.path == picks.second }?.let { diskTitle(it) } ?: none,
                options = free.filter { it.path != picks.first }.map { disk -> diskTitle(disk) to { update(picks.copy(second = disk.path)) } },
                showDivider = false,
            )
        }
    }
}

@Composable
private fun ChangePreview(change: ArrayChange, hardware: ServerHardware) {
    val preview = change.preview(hardware)
    GroupedSection(header = stringResource(R.string.storage_what_changes)) {
        if (preview.usableBefore > 0 && change.action != ArrayChange.Action.DELETE) {
            ValueRow(stringResource(R.string.storage_space), "${bytes(preview.usableBefore)} → ${bytes(preview.usableAfter)}", null)
            ValueRow(stringResource(R.string.storage_may_fail), "${preview.failuresBefore} → ${preview.failuresAfter}", null)
        }
        if (preview.takesLong) ValueRow(stringResource(R.string.storage_takes_long), null, null)
        if (preview.goesOffline) ValueRow(stringResource(R.string.storage_goes_offline), null, null)
        if (preview.failuresBefore > 0 && preview.failuresAfter == 0 && change.action != ArrayChange.Action.DELETE) {
            ValueRow(stringResource(R.string.storage_unprotected), null, null)
        }
        if (change.action in setOf(ArrayChange.Action.REMOVE, ArrayChange.Action.CHANGE_LEVEL, ArrayChange.Action.DELETE)) {
            ValueRow(stringResource(R.string.storage_backup_first), null, null)
        }
        val member = change.member
        if (member != null && (change.action == ArrayChange.Action.DETACH || change.action == ArrayChange.Action.REPLACE)) {
            ValueRow(stringResource(R.string.storage_pull_out, memberTitle(member, hardware)), null, null, showDivider = false)
        }
    }
}

@Composable
private fun ChangeConfirm(
    action: ArrayChange.Action,
    arrayName: String,
    erases: Boolean,
    word: String,
    picks: ChangePicks,
    update: (ChangePicks) -> Unit,
) {
    val deletes = action == ArrayChange.Action.DELETE
    if (!deletes && !erases) return
    val prompt = if (deletes) stringResource(R.string.storage_delete_confirm, arrayName)
    else stringResource(R.string.storage_new_disk_erased, word)
    GroupedSection(footer = prompt) {
        FieldRow(
            label = if (deletes) arrayName else word,
            value = picks.typed,
            onValueChange = { update(picks.copy(typed = it)) },
            placeholder = if (deletes) arrayName else word,
            showDivider = false,
        )
    }
}
