package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationKind
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.servercontrol.ANSIStripper
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.OutputTail
import com.skaymer.gryonixnexus.servercontrol.PurgeOptions
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.UninstallOperations
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

fun interface HostCleanup {
    suspend fun fullCleanup(purge: PurgeOptions, onEvent: (UninstallOperations.Event) -> Unit)
}

enum class EraseWarning { NOTHING_DELETED, DATA, BACKUPS, DATA_AND_BACKUPS }

/** One erase in flight, and how it ended */
data class EraseRun(
    val deploymentID: String,
    val purge: PurgeOptions,
    val host: SSHHostID? = null,
    val finished: List<SSHHostID> = emptyList(),
    /** What the machine printed, as a person reads it */
    val log: String = "",
    val isFinished: Boolean = false,
    /** Every machine is clean */
    val erased: Boolean = false,
    val errorMessage: String? = null,
)

class EraseViewModel(
    private val scope: CoroutineScope,
    private val cleanups: suspend (Deployment) -> HostCleanup,
    private val release: suspend (Deployment) -> Unit = {},
) {
    private val _run = MutableStateFlow<EraseRun?>(null)
    val run: StateFlow<EraseRun?> = _run.asStateFlow()

    fun erase(deployment: Deployment, purge: PurgeOptions) {
        if (_run.value?.isFinished == false) return
        _run.value = EraseRun(deploymentID = deployment.id, purge = purge)
        scope.launch {
            val notice = OperationNotices.start(
                R.string.notice_erasing, deployment.name, server = deployment.name, kind = OperationKind.REMOVAL,
            )
            try {
                cleanups(deployment).fullCleanup(purge) { event ->
                    if (event is UninstallOperations.Event.Output) notice.update(OperationNotices.lastLine(event.text))
                    when (event) {
                        is UninstallOperations.Event.HostStarted -> mutate { it.copy(host = event.host) }
                        is UninstallOperations.Event.Output -> mutate {
                            it.copy(
                                log = OutputTail.tail(
                                    WrapperLogText.readable(ANSIStripper.strip(it.log + event.text))
                                )
                            )
                        }
                        is UninstallOperations.Event.HostFinished ->
                            mutate { it.copy(host = null, finished = it.finished + event.host) }
                    }
                }
                mutate { it.copy(host = null, isFinished = true, erased = true) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                mutate { it.copy(host = null, isFinished = true, errorMessage = reason(failure)) }
            }
            notice.finish(OperationNotices.text(R.string.notice_done), _run.value?.errorMessage)
        }
    }

    fun clear() {
        if (_run.value?.isFinished == true) _run.value = null
    }

    private fun mutate(change: (EraseRun) -> EraseRun) {
        _run.value = _run.value?.let(change)
    }

    private fun reason(failure: Exception): String =
        failure.message ?: failure::class.simpleName.orEmpty()

    companion object {
        fun warning(purge: PurgeOptions): EraseWarning = when {
            purge.data && purge.backups -> EraseWarning.DATA_AND_BACKUPS
            purge.data -> EraseWarning.DATA
            purge.backups -> EraseWarning.BACKUPS
            else -> EraseWarning.NOTHING_DELETED
        }
    }
}
