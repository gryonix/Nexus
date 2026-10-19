package com.skaymer.gryonixnexus.app.install

import com.skaymer.gryonixnexus.catalog.storage.FastStoragePlan
import com.skaymer.gryonixnexus.catalog.storage.RaidImportPlan
import com.skaymer.gryonixnexus.catalog.storage.RaidPlan
import com.skaymer.gryonixnexus.catalog.storage.ServerDisk
import com.skaymer.gryonixnexus.catalog.storage.ServerHardware
import com.skaymer.gryonixnexus.catalog.storage.StorageArray
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import java.util.Base64
import kotlin.time.Duration.Companion.seconds

/** Storage the user picked for one machine */
data class StorageChoice(
    /** A disk path, or `array:<id>` for a found mirror */
    val fastDisk: String? = null,
    /** Second SSD that mirrors the cache disk */
    val mirrorDisk: String? = null,
    /** Arrays found on the disks that are brought back */
    val importArrays: Set<String> = emptySet(),
    val buildsRaid: Boolean = false,
    val raidLevel: RaidPlan.Level = RaidPlan.Level.RAID1,
    /** mdadm, ZFS or btrfs */
    val raidKind: StorageArray.Kind = StorageArray.Kind.MD,
    val raidDisks: Set<String> = emptySet(),
    val confirmation: String = "",
    /** The typed confirmation matches the erase word */
    val confirmed: Boolean = false,
) {
    companion object {
        const val ARRAY_PREFIX = "array:"

        /** Brings back everything a past install left */
        fun defaults(hardware: ServerHardware): StorageChoice {
            val stopped = StorageArray.all(hardware)
                .filter { it.state == StorageArray.State.Stopped && it.kind == StorageArray.Kind.MD }
            val mirror = stopped.firstOrNull { it.isCacheMirror }
            val earlier = hardware.disks.firstOrNull { it.isEarlierCache }
            return StorageChoice(
                importArrays = stopped.map { it.id }.toSet(),
                fastDisk = mirror?.let { ARRAY_PREFIX + it.id } ?: earlier?.path,
            )
        }
    }
}

/** One script run before setup, with its success marker */
data class StorageStep(
    val kind: Kind,
    val script: String,
    val doneMarker: String,
    val name: String = "",
    /** The same work as a typed agent request */
    val agentTask: gryonixnexusd.v1.StorageTaskRequest? = null,
) {
    enum class Kind { IMPORT, MIRROR, RAID, CACHE, HEALTH, CHANGE, SWAP }
}

val InstallTarget.arrays: List<StorageArray> get() = hardware?.let { StorageArray.all(it) }.orEmpty()

val InstallTarget.fastDisk: ServerDisk? get() = hardware?.disks?.firstOrNull { it.path == storage.fastDisk }

val InstallTarget.mirrorPlan: RaidPlan?
    get() {
        val first = fastDisk?.takeIf { it.isBlank } ?: return null
        val second = hardware?.disks?.firstOrNull { it.path == storage.mirrorDisk } ?: return null
        return RaidPlan.cacheMirror(listOf(first, second))
    }

/** The cache sits on one disk with nothing mirroring it */
val InstallTarget.cacheIsSingleDisk: Boolean get() = fastDisk != null && mirrorPlan == null

val InstallTarget.raidPlan: RaidPlan?
    get() {
        val hardware = hardware ?: return null
        if (!storage.buildsRaid) return null
        val disks = RaidPlan.candidates(hardware).filter { it.path in storage.raidDisks }
        return RaidPlan(storage.raidLevel, disks, kind = storage.raidKind)
    }

val InstallTarget.fastPlan: FastStoragePlan?
    get() {
        val hot = FastStoragePlan.hotPathsInText(script.contents)
        mirrorPlan?.let { return FastStoragePlan(FastStoragePlan.Target.Device(it.device), hot) }
        val choice = storage.fastDisk ?: return null
        if (choice.startsWith(StorageChoice.ARRAY_PREFIX)) {
            val array = arrays.firstOrNull { it.id == choice.removePrefix(StorageChoice.ARRAY_PREFIX) } ?: return null
            return FastStoragePlan(FastStoragePlan.Target.Device(array.address), hot)
        }
        return fastDisk?.let { FastStoragePlan(it, hot) }
    }

/** RAID needs enough disks and the typed confirmation */
val InstallTarget.storageIsReady: Boolean
    get() {
        val raid = raidPlan ?: return true
        return raid.isValid && storage.confirmed
    }

val InstallTarget.storageSteps: List<StorageStep>
    get() = arrays.filter { it.state == StorageArray.State.Stopped && it.id in storage.importArrays }
        .map { StorageStep(StorageStep.Kind.IMPORT, RaidImportPlan(it).script(), RaidImportPlan.DONE_MARKER, it.name) } +
        listOfNotNull(
            mirrorPlan?.let { StorageStep(StorageStep.Kind.MIRROR, it.script(), RaidPlan.DONE_MARKER) },
            raidPlan?.takeIf { it.isValid }?.let { StorageStep(StorageStep.Kind.RAID, it.script(), RaidPlan.DONE_MARKER) },
            fastPlan?.let { StorageStep(StorageStep.Kind.CACHE, it.script(), FastStoragePlan.DONE_MARKER) },
        )

object StoragePreparation {
    class Failure(message: String) : Exception(message)

    /** Uploads the script, runs it as root, checks its marker */
    suspend fun run(step: StorageStep, runner: SSHCommandRunner, username: String) {
        output(step.script, step.doneMarker, runner, SSHHostID.VPS, elevated = username != "root")
    }

    /** Runs the script on `host` and returns its output */
    suspend fun output(script: String, doneMarker: String, runner: SSHCommandRunner, host: SSHHostID, elevated: Boolean): String {
        val encoded = Base64.getEncoder().encodeToString(script.toByteArray())
        val elevate = if (elevated) "sudo -n " else ""
        val command = "f=\"\$(mktemp)\" && printf '%s' '$encoded' | base64 -d > \"\$f\" && " +
            "{ ${elevate}bash \"\$f\" 2>&1; rc=\$?; rm -f \"\$f\"; exit \$rc; }"
        val result = runner.run(command, host, 900.seconds)
        if (doneMarker !in result.stdout) {
            val tail = (result.stdout + result.stderr).lines().takeLast(6).joinToString("\n")
            throw Failure(tail)
        }
        return result.stdout
    }
}
