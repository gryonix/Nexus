package com.skaymer.gryonixnexus.app.containers

import com.skaymer.gryonixnexus.agentcontrol.AgentContainerOperations
import com.skaymer.gryonixnexus.agentcontrol.ContainerAction
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupCadence
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupPlan
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupRunEvent
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupListing
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupSchedule
import com.skaymer.gryonixnexus.agentcontrol.ContainerDetail
import com.skaymer.gryonixnexus.agentcontrol.ContainerInventory
import com.skaymer.gryonixnexus.agentcontrol.ContainerLogLine
import com.skaymer.gryonixnexus.agentcontrol.ContainerRemovalEvent
import com.skaymer.gryonixnexus.agentcontrol.ContainerRemovalPreview
import com.skaymer.gryonixnexus.agentcontrol.ContainerUpdateEvent
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.last

/** What the containers section asks of a server */
interface ContainerManaging {
    suspend fun inventory(): ContainerInventory
    suspend fun rename(key: String, to: String): ContainerInventory
    suspend fun control(key: String, action: ContainerAction)
    suspend fun inspect(container: String): ContainerDetail

    fun logs(key: String, tail: Int): Flow<ContainerLogLine>

    suspend fun backupPlan(key: String): ContainerBackupPlan

    suspend fun setBackupPlan(key: String, plan: ContainerBackupPlan?): ContainerBackupPlan

    suspend fun backupSchedule(key: String): ContainerBackupSchedule
    suspend fun setBackupSchedule(key: String, every: ContainerBackupCadence?): ContainerBackupSchedule

    /** The archives this group's runs have left, newest first */
    suspend fun backups(key: String): ContainerBackupListing

    suspend fun removalPreview(
        key: String,
        purgeData: Boolean,
        purgeBackups: Boolean,
    ): ContainerRemovalPreview

    fun runBackup(key: String): Flow<ContainerBackupRunEvent>
    fun remove(key: String, purgeData: Boolean, purgeBackups: Boolean): Flow<ContainerRemovalEvent>
    fun update(key: String, skipBackup: Boolean): Flow<ContainerUpdateEvent>
}

class AgentContainers(private val operations: AgentContainerOperations) : ContainerManaging {
    override suspend fun inventory() = operations.inventory()

    override suspend fun rename(key: String, to: String) = operations.rename(key, to)

    override suspend fun control(key: String, action: ContainerAction) {
        operations.control(key, action).last()
    }

    override suspend fun inspect(container: String) = operations.inspect(container)

    override fun logs(key: String, tail: Int) = operations.logs(key, tail)

    override suspend fun backupPlan(key: String) = operations.backupPlan(key)

    override suspend fun setBackupPlan(key: String, plan: ContainerBackupPlan?) =
        operations.setBackupPlan(key, plan)

    override suspend fun backupSchedule(key: String) = operations.backupSchedule(key)

    override suspend fun backups(key: String) = operations.backups(key)

    override suspend fun setBackupSchedule(key: String, every: ContainerBackupCadence?) =
        operations.setBackupSchedule(key, every)

    override suspend fun removalPreview(key: String, purgeData: Boolean, purgeBackups: Boolean) =
        operations.removalPreview(key, purgeData, purgeBackups)

    override fun runBackup(key: String) = operations.runBackup(key)

    override fun remove(key: String, purgeData: Boolean, purgeBackups: Boolean) =
        operations.remove(key, purgeData, purgeBackups)

    override fun update(key: String, skipBackup: Boolean) = operations.update(key, skipBackup)
}
