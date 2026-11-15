package com.skaymer.gryonixnexus.app.notify

import com.skaymer.gryonixnexus.agentclient.AgentError

/** A stop that found nothing to act on */
class StopMiss(val reason: StopRefusalText.Reason) : Exception()

/** Why a server did not stop an operation */
object StopRefusalText {
    sealed interface Reason {
        data object CannotStop : Reason

        data object NothingRunning : Reason

        data object ServerGone : Reason

        data class Failed(val detail: String) : Reason
    }

    fun reason(error: Throwable): Reason = when {
        error is StopMiss -> error.reason
        error is AgentError.Rpc && error.code == "failed_precondition" -> Reason.CannotStop
        else -> Reason.Failed(error.message ?: error.javaClass.simpleName)
    }
}
