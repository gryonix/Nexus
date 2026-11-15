package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.BackupPartsChange
import com.skaymer.gryonixnexus.servercontrol.BackupPartsState
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the backup parts screen shows */
data class BackupPartsScreen(
    val parts: BackupPartsState = BackupPartsState(),
    /** Services with backups turned on */
    val listed: List<String> = emptyList(),
    val loaded: Boolean = false,
    val error: String? = null,
)

/** Which parts backups copy on one server: read and change */
class BackupPartsModel(
    private val scope: CoroutineScope,
    private val schedules: suspend (Deployment) -> BackupScheduleManaging,
) {
    private val _state = MutableStateFlow(BackupPartsScreen())
    val state: StateFlow<BackupPartsScreen> = _state.asStateFlow()

    fun load(deployment: Deployment) {
        if (DemoDeployments.isDemoID(deployment.id)) {
            _state.value = _state.value.copy(loaded = true)
            return
        }
        scope.launch {
            try {
                val seam = schedules(deployment)
                val listed = seam.load().services.sorted()
                _state.value = BackupPartsScreen(parts = seam.loadParts(), listed = listed, loaded = true)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.value = _state.value.copy(loaded = true, error = e.message)
            }
        }
    }

    /** Shows the change now, reverts if refused */
    fun save(deployment: Deployment, change: BackupPartsChange) {
        val previous = _state.value
        _state.value = previous.copy(parts = previous.parts.applying(change), error = null)
        if (DemoDeployments.isDemoID(deployment.id)) return
        scope.launch {
            try {
                schedules(deployment).saveParts(change)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.value = previous.copy(error = e.message)
            }
        }
    }
}
