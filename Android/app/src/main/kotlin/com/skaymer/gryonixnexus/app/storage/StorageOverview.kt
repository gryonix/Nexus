package com.skaymer.gryonixnexus.app.storage

import com.skaymer.gryonixnexus.catalog.storage.FastStoragePlan
import com.skaymer.gryonixnexus.catalog.storage.ServerHardware
import com.skaymer.gryonixnexus.catalog.storage.StorageArray
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the General tab knows about each machine's disks */
class StorageOverview(
    private val scope: CoroutineScope,
    private val control: suspend (Deployment) -> SSHCommandRunner,
) {
    private val _hardware = MutableStateFlow<Map<SSHHostID, ServerHardware>>(emptyMap())
    val hardware: StateFlow<Map<SSHHostID, ServerHardware>> = _hardware.asStateFlow()
    private var loadedFor: String? = null

    fun load(deployment: Deployment) {
        if (loadedFor == deployment.id) return
        loadedFor = deployment.id
        _hardware.value = emptyMap()
        scope.launch {
            for (node in deployment.nodes) {
                val parsed = try {
                    ServerHardware.parse(control(deployment).run(ServerHardware.PROBE_COMMAND, node.sshHost, 20.seconds).stdout)
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (failure: Exception) {
                    null
                } ?: continue
                _hardware.value = _hardware.value + (node.sshHost to parsed)
            }
        }
    }

    companion object {
        /** Needs two disks or an existing array */
        fun manages(hardware: ServerHardware): Boolean =
            hardware.disks.size >= 2 || StorageArray.all(hardware).isNotEmpty()

        fun offersCache(hardware: ServerHardware): Boolean = FastStoragePlan.candidates(hardware).isNotEmpty()
    }
}
