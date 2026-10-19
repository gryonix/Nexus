package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.storage.BackupDrive
import com.skaymer.gryonixnexus.catalog.storage.BackupDriveCheck
import com.skaymer.gryonixnexus.catalog.storage.BackupDrives
import com.skaymer.gryonixnexus.catalog.storage.ServerHardware
import com.skaymer.gryonixnexus.servercontrol.BackupDriveSettings
import com.skaymer.gryonixnexus.servercontrol.BackupDriveStatus
import com.skaymer.gryonixnexus.servercontrol.BackupDrivesState
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the USB drives screen shows */
data class BackupDrivesScreen(
    val drives: BackupDrivesState = BackupDrivesState(),
    val loaded: Boolean = false,
    val busy: Boolean = false,
    val error: String? = null,
    val checks: Map<String, BackupDriveCheck> = emptyMap(),
)

/** USB drive settings for one server: read, change, remember checks */
class BackupDrivesModel(
    private val scope: CoroutineScope,
    private val schedules: suspend (Deployment) -> BackupScheduleManaging,
) {
    private val _state = MutableStateFlow(BackupDrivesScreen())
    val state: StateFlow<BackupDrivesScreen> = _state.asStateFlow()

    fun load(deployment: Deployment) = work {
        val drives = if (DemoDeployments.isDemoID(deployment.id)) BackupDrivesDemo.state else schedules(deployment).loadDrives()
        _state.value = _state.value.copy(drives = drives, loaded = true)
    }

    fun save(deployment: Deployment, settings: BackupDriveSettings) = work {
        if (DemoDeployments.isDemoID(deployment.id)) {
            _state.value = _state.value.copy(drives = _state.value.drives.copy(settings = settings))
            return@work
        }
        val seam = schedules(deployment)
        seam.saveDrives(settings)
        _state.value = _state.value.copy(drives = seam.loadDrives())
    }

    fun setUsed(deployment: Deployment, uuid: String, used: Boolean) {
        val settings = _state.value.drives.settings
        val uuids = settings.uuids.filter { it != uuid } + if (used) listOf(uuid) else emptyList()
        save(deployment, settings.copy(uuids = uuids))
    }

    /** Uses a newly formatted drive in place of its predecessors */
    fun formatted(deployment: Deployment, uuid: String, replacing: String?, name: String) =
        save(deployment, _state.value.drives.settingsAfterFormat(uuid, replacing, name))

    /** Stops using a forgotten drive */
    fun forgotten(deployment: Deployment, uuid: String) {
        if (uuid in _state.value.drives.settings.uuids) setUsed(deployment, uuid, false) else load(deployment)
    }

    /** Stores the passphrase encrypted copies are made with */
    fun savePassphrase(deployment: Deployment, passphrase: String) = work {
        val seam = schedules(deployment)
        seam.save(seam.load(), passphrase)
        _state.value = _state.value.copy(drives = seam.loadDrives())
    }

    fun remember(driveID: String, check: BackupDriveCheck) {
        _state.value = _state.value.copy(checks = _state.value.checks + (driveID to check))
    }

    private fun work(body: suspend () -> Unit) {
        _state.value = _state.value.copy(busy = true, error = null)
        scope.launch {
            val failure = try {
                body()
                null
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                error.message ?: error.toString()
            }
            _state.value = _state.value.copy(busy = false, error = failure)
        }
    }

    companion object {
        /** Drives the server sees, plus missing chosen ones */
        fun drives(hardware: ServerHardware?, state: BackupDrivesState): List<BackupDrive> {
            val names = state.namesByUuid
            return BackupDrives.drives(hardware, state.settings.uuids.associateWith { names[it] ?: it })
        }

        fun status(drive: BackupDrive, state: BackupDrivesState): BackupDriveStatus? =
            state.statuses.firstOrNull { it.uuid == drive.uuid }
    }
}

/** A fictional server's drives, for the demo */
object BackupDrivesDemo {
    const val UUID = "0d3e5f7a-1b2c-4d5e-8f90-a1b2c3d4e5f6"

    val state = BackupDrivesState(
        settings = BackupDriveSettings(uuids = listOf(UUID)),
        statuses = listOf(BackupDriveStatus(UUID, true, 61_530_439_680, 29_000_000_000, "/srv/gryonix-backup/usb1")),
        lastCopyAt = System.currentTimeMillis() / 1000 - 3 * 3600,
        lastCopySucceeded = true,
        hasPassphrase = true,
    )

    const val PROBE = "GRYONIXNEXUS_HW_BEGIN\ncpu=4\nmem=8221114368\narch=aarch64\nrootfree=402653184000\n" +
        "lsblk={\"blockdevices\":[{\"name\":\"sda\",\"path\":\"/dev/sda\",\"size\":500107862016,\"rota\":false,\"type\":\"disk\"," +
        "\"model\":\"Demo SSD\",\"tran\":\"sata\",\"children\":[{\"name\":\"sda1\",\"path\":\"/dev/sda1\",\"type\":\"part\"," +
        "\"mountpoint\":\"/\",\"fstype\":\"ext4\"}]},{\"name\":\"sdb\",\"path\":\"/dev/sdb\",\"size\":61530439680,\"rota\":false," +
        "\"type\":\"disk\",\"model\":\"Demo Stick\",\"tran\":\"usb\",\"rm\":true,\"hotplug\":true,\"children\":[{\"name\":\"sdb1\"," +
        "\"path\":\"/dev/sdb1\",\"type\":\"part\",\"mountpoint\":\"/srv/gryonix-backup/usb1\",\"fstype\":\"ext4\"," +
        "\"label\":\"gnxb-usb1\",\"uuid\":\"$UUID\"}]},{\"name\":\"sdc\",\"path\":\"/dev/sdc\",\"size\":1000204886016," +
        "\"rota\":true,\"type\":\"disk\",\"model\":\"Demo Portable\",\"tran\":\"usb\",\"rm\":false,\"hotplug\":true}]}\n" +
        "GRYONIXNEXUS_HW_END\n"

    val check = BackupDriveCheck(
        filesystem = BackupDriveCheck.Filesystem.CLEAN,
        writeBytesPerSecond = 31_457_280,
        readBytesPerSecond = 104_857_600,
    )
}
