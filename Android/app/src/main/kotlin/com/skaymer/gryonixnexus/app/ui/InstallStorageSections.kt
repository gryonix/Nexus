package com.skaymer.gryonixnexus.app.ui

import android.text.format.Formatter
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.install.InstallTarget
import com.skaymer.gryonixnexus.app.install.InstallViewModel
import com.skaymer.gryonixnexus.app.install.StorageChoice
import com.skaymer.gryonixnexus.app.install.arrays
import com.skaymer.gryonixnexus.app.install.cacheIsSingleDisk
import com.skaymer.gryonixnexus.app.install.fastDisk
import com.skaymer.gryonixnexus.catalog.storage.StorageArray
import com.skaymer.gryonixnexus.app.install.fastPlan
import com.skaymer.gryonixnexus.app.install.raidPlan
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.catalog.ServerRequirements
import com.skaymer.gryonixnexus.catalog.storage.FastStoragePlan
import com.skaymer.gryonixnexus.catalog.storage.HardwareVerdict
import com.skaymer.gryonixnexus.catalog.storage.RaidPlan
import com.skaymer.gryonixnexus.catalog.storage.ServerDisk
import com.skaymer.gryonixnexus.catalog.storage.ServerHardware

/** Server hardware, its fit, and how its disks are used */
@Composable
fun InstallStorageSections(
    model: InstallViewModel,
    target: InstallTarget,
    requirements: ServerRequirements,
    isRelay: Boolean = false,
) {
    val hardware = target.hardware ?: return
    FoundHardwareSection(hardware, HardwareVerdict.judge(hardware, requirements))
    if (isRelay) return
    if (target.arrays.isNotEmpty()) {
        ExistingArraysSection(target) { change -> model.edit(target.slot) { it.copy(storage = change(it.storage)) } }
    }
    CacheDiskSection(target, hardware) { change -> model.edit(target.slot) { it.copy(storage = change(it.storage)) } }
    RaidSection(target, hardware) { change -> model.edit(target.slot) { it.copy(storage = change(it.storage)) } }
}

@Composable
internal fun bytes(value: Long): String = Formatter.formatFileSize(LocalContext.current, value)

@Composable
internal fun diskState(disk: ServerDisk): String = when {
    disk.isSystem -> stringResource(R.string.storage_system_disk)
    disk.raidMember -> stringResource(R.string.storage_in_raid)
    disk.dataMount != null -> stringResource(R.string.storage_mounted_at, disk.dataMount!!)
    disk.isBlank -> stringResource(R.string.storage_empty)
    else -> stringResource(R.string.storage_holds_data)
}

@Composable
internal fun diskDetail(disk: ServerDisk): String {
    val kind = when (disk.kind) {
        ServerDisk.Kind.NVME -> "NVMe"
        ServerDisk.Kind.SSD -> "SSD"
        ServerDisk.Kind.HDD -> "HDD"
    }
    return "$kind · ${bytes(disk.sizeBytes)} · ${diskState(disk)}"
}

internal fun diskTitle(disk: ServerDisk) = listOf(disk.name, disk.model).filter { it.isNotEmpty() }.joinToString(" · ")

@Composable
private fun FoundHardwareSection(hardware: ServerHardware, verdict: HardwareVerdict) {
    GroupedSection(header = stringResource(R.string.storage_found), footer = verdictDetail(verdict)) {
        ValueRow(title = verdictTitle(verdict), value = null, onClick = null)
        ValueRow(stringResource(R.string.storage_processor), stringResource(R.string.storage_cores, hardware.cpuCores), null)
        ValueRow(stringResource(R.string.storage_memory), bytes(hardware.memoryBytes), null)
        ValueRow(stringResource(R.string.storage_swap), currentSwap(hardware.swapBytes), null)
        ValueRow(stringResource(R.string.storage_free_system), bytes(hardware.rootFreeBytes), null)
        ValueRow(stringResource(R.string.storage_architecture), hardware.architecture, null)
        hardware.disks.forEach { disk ->
            ValueRow(diskTitle(disk), value = null, onClick = null, subtitle = diskDetail(disk),
                showDivider = disk != hardware.disks.last())
        }
    }
}

@Composable
private fun verdictTitle(verdict: HardwareVerdict): String = stringResource(
    when (verdict.level) {
        HardwareVerdict.Level.FITS -> R.string.storage_fits
        HardwareVerdict.Level.TIGHT -> R.string.storage_tight
        HardwareVerdict.Level.DOES_NOT_FIT -> R.string.storage_too_small
    }
)

@Composable
private fun verdictDetail(verdict: HardwareVerdict): String? {
    val lines = verdict.findings.filter { it.level != HardwareVerdict.Level.FITS }.map { finding ->
        val res = if (finding.resource == HardwareVerdict.Resource.MEMORY) R.string.storage_memory_needs else R.string.storage_disk_needs
        val have = if (finding.swapBytes > 0) {
            stringResource(R.string.swap_with_ram, bytes(finding.haveBytes), bytes(finding.swapBytes))
        } else {
            bytes(finding.haveBytes)
        }
        stringResource(res, have, bytes(finding.needBytes))
    }
    return lines.takeIf { it.isNotEmpty() }?.joinToString("\n")
}

@Composable
private fun CacheDiskSection(target: InstallTarget, hardware: ServerHardware, update: ((StorageChoice) -> StorageChoice) -> Unit) {
    val candidates = FastStoragePlan.candidates(hardware)
        .filter { !(target.storage.buildsRaid && it.path in target.storage.raidDisks) }
    val mirrors = target.arrays.filter { it.isCacheMirror && it.state == StorageArray.State.Stopped }
    val partners = target.fastDisk?.takeIf { it.isBlank }?.let { first ->
        candidates.filter { it.isBlank && it.path != first.path }
    }.orEmpty()
    val earlier = target.fastDisk?.isEarlierCache == true ||
        target.storage.fastDisk?.startsWith(StorageChoice.ARRAY_PREFIX) == true
    val footer = when {
        earlier -> stringResource(R.string.storage_cache_earlier_note)
        target.fastPlan?.target is FastStoragePlan.Target.Device -> stringResource(R.string.storage_cache_blank_note)
        target.fastPlan != null -> stringResource(R.string.storage_cache_mounted_note)
        else -> stringResource(R.string.storage_cache_note)
    }
    GroupedSection(header = stringResource(R.string.storage_cache_disk), footer = footer) {
        if (candidates.isEmpty() && mirrors.isEmpty()) {
            ValueRow(stringResource(R.string.storage_no_fast_disk), null, null, showDivider = false)
            return@GroupedSection
        }
        val none = stringResource(R.string.storage_none)
        val mirrorTitle = stringResource(R.string.storage_cache_mirror_earlier)
        val options = listOf<Pair<String, String?>>(none to null) +
            mirrors.map { mirrorTitle to StorageChoice.ARRAY_PREFIX + it.id } +
            candidates.map { diskChoice(it) to it.path }
        ChoiceRow(
            title = stringResource(R.string.storage_cache_disk),
            value = options.firstOrNull { it.second == target.storage.fastDisk }?.first ?: none,
            showDivider = partners.isNotEmpty() || target.cacheIsSingleDisk,
            options = options.map { (label, value) -> label to { update { it.copy(fastDisk = value, mirrorDisk = null) } } },
        )
        if (partners.isNotEmpty()) {
            val chosen = partners.firstOrNull { it.path == target.storage.mirrorDisk }
            ChoiceRow(
                title = stringResource(R.string.storage_mirror_onto),
                value = chosen?.let { diskChoice(it) } ?: none,
                showDivider = target.cacheIsSingleDisk,
                options = listOf(none to { update { it.copy(mirrorDisk = null) } }) +
                    partners.map { disk -> diskChoice(disk) to { update { it.copy(mirrorDisk = disk.path) } } },
            )
        }
        if (target.cacheIsSingleDisk) {
            ValueRow(stringResource(R.string.storage_single_ssd_warning), null, null, showDivider = false)
        }
    }
}

@Composable
private fun diskChoice(disk: ServerDisk): String {
    val base = "${disk.name} · ${bytes(disk.sizeBytes)}"
    return if (disk.isEarlierCache) base + " · " + stringResource(R.string.storage_from_earlier) else base
}

@Composable
private fun ExistingArraysSection(target: InstallTarget, update: ((StorageChoice) -> StorageChoice) -> Unit) {
    GroupedSection(
        header = stringResource(R.string.storage_arrays_here),
        footer = stringResource(R.string.storage_arrays_here_note),
    ) {
        target.arrays.forEach { array ->
            if (array.state == StorageArray.State.Stopped && array.repairsHere) {
                ToggleRow(
                    title = arrayTitle(array),
                    subtitle = arrayState(array),
                    checked = array.id in target.storage.importArrays,
                    onCheckedChange = { on ->
                        update { it.copy(importArrays = if (on) it.importArrays + array.id else it.importArrays - array.id) }
                    },
                    showDivider = array != target.arrays.last(),
                )
            } else {
                ValueRow(arrayTitle(array), null, null, subtitle = arrayState(array),
                    showDivider = array != target.arrays.last())
            }
        }
    }
}

fun arrayTitle(array: StorageArray): String =
    listOf(array.name, array.level.uppercase()).filter { it.isNotEmpty() }.joinToString(" · ")

@Composable
fun arrayState(array: StorageArray): String {
    val spares = array.spares.map { stringResource(R.string.storage_spare_member, it.removePrefix("/dev/")) }
    val members = (array.members.map { it.removePrefix("/dev/") } + array.failed.map { it.removePrefix("/dev/") + " ✕" } + spares)
        .joinToString(", ") + (array.mountpoint?.let { " → $it" } ?: "")
    val state = if (array.isForeignSystemPool) stringResource(R.string.storage_array_foreign_system) else when (val current = array.state) {
        StorageArray.State.Clean -> stringResource(R.string.storage_array_healthy)
        StorageArray.State.Degraded -> stringResource(R.string.storage_array_degraded, array.working, array.slots)
        is StorageArray.State.Rebuilding -> stringResource(R.string.storage_array_rebuilding, current.percent.toInt())
        is StorageArray.State.Checking -> stringResource(R.string.storage_array_checking, current.percent.toInt())
        StorageArray.State.Stopped -> stringResource(R.string.storage_array_stopped)
        StorageArray.State.Unknown -> stringResource(
            if (array.kind == StorageArray.Kind.HARDWARE) R.string.storage_array_controller
            else R.string.storage_array_unknown,
        )
    }
    return "$members\n$state"
}

@Composable
private fun RaidSection(target: InstallTarget, hardware: ServerHardware, update: ((StorageChoice) -> StorageChoice) -> Unit) {
    val candidates = RaidPlan.candidates(hardware)
        .filter { it.path != target.storage.fastDisk && it.path != target.storage.mirrorDisk }
    if (candidates.size < 2) return
    GroupedSection(
        header = stringResource(R.string.storage_raid),
        footer = stringResource(R.string.storage_raid_mount_note, RaidPlan.MOUNT_POINT),
    ) {
        ToggleRow(
            title = stringResource(R.string.storage_build_raid),
            checked = target.storage.buildsRaid,
            onCheckedChange = { on -> update { it.copy(buildsRaid = on) } },
            showDivider = target.storage.buildsRaid,
        )
        if (target.storage.buildsRaid) RaidChoiceRows(target.storage, target.raidPlan, candidates, update)
    }
}

@Composable
internal fun RaidChoiceRows(
    choice: StorageChoice,
    plan: RaidPlan?,
    candidates: List<ServerDisk>,
    update: ((StorageChoice) -> StorageChoice) -> Unit,
) {
    ChoiceRow(
        title = stringResource(R.string.storage_kind),
        value = kindTitle(choice.raidKind),
        options = RaidPlan.BUILDABLE_KINDS.map { kind ->
            kindTitle(kind) to {
                update { it.copy(raidKind = kind, raidLevel = if (it.raidLevel in RaidPlan.levels(kind)) it.raidLevel else RaidPlan.Level.RAID1) }
            }
        },
    )
    ValueRow(kindNote(choice.raidKind), null, null)
    ChoiceRow(
        title = stringResource(R.string.storage_level),
        value = levelTitle(choice.raidLevel),
        options = RaidPlan.levels(choice.raidKind).map { level -> levelTitle(level) to { update { it.copy(raidLevel = level) } } },
    )
    candidates.forEach { disk ->
        CheckRow(
            title = diskTitle(disk),
            subtitle = diskDetail(disk),
            checked = disk.path in choice.raidDisks,
            onClick = {
                update { current ->
                    val disks = if (disk.path in current.raidDisks) current.raidDisks - disk.path else current.raidDisks + disk.path
                    current.copy(raidDisks = disks)
                }
            },
        )
    }
    RaidSummary(plan)
    if (choice.raidLevel == RaidPlan.Level.RAID0) {
        ValueRow(stringResource(R.string.storage_raid0_warning), null, null)
    }
    val word = stringResource(R.string.storage_erase_word)
    FieldRow(
        label = stringResource(R.string.storage_erase_prompt, word),
        value = choice.confirmation,
        onValueChange = { typed ->
            update { it.copy(confirmation = typed, confirmed = typed.trim().equals(word, ignoreCase = true)) }
        },
        placeholder = word,
        showDivider = false,
    )
}

@Composable
private fun RaidSummary(plan: RaidPlan?) {
    plan ?: return
    when {
        plan.isValid -> {
            ValueRow(stringResource(R.string.storage_usable), bytes(plan.usableBytes), null)
            ValueRow(stringResource(R.string.storage_may_fail), plan.survivableFailures.toString(), null)
        }
        plan.level == RaidPlan.Level.RAID10 && plan.disks.size % 2 != 0 ->
            ValueRow(stringResource(R.string.storage_raid10_even), null, null)
        else -> ValueRow(stringResource(R.string.storage_pick_at_least, plan.level.minimumDisks), null, null)
    }
    if (plan.disks.any { !it.isBlank }) ValueRow(stringResource(R.string.storage_disk_has_data), null, null)
}

@Composable
internal fun levelTitle(level: RaidPlan.Level): String = stringResource(
    when (level) {
        RaidPlan.Level.RAID0 -> R.string.storage_raid0
        RaidPlan.Level.RAID1 -> R.string.storage_raid1
        RaidPlan.Level.RAID5 -> R.string.storage_raid5
        RaidPlan.Level.RAID6 -> R.string.storage_raid6
        RaidPlan.Level.RAID10 -> R.string.storage_raid10
    }
)
