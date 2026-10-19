package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import com.skaymer.gryonixnexus.catalog.ServiceID

object AgentAdoption {
    enum class Stage { CONNECTING, PAIRING, DISCOVERING }

    sealed interface Failure {
        val detail: String

        /** SSH did not get through */
        data class Unreachable(override val detail: String) : Failure

        data class KeyRefused(override val detail: String) : Failure

        /** Connected, and nothing answered as `gryonixnexusd` */
        data class NoAgent(override val detail: String) : Failure

        /** The agent answered and then a step failed */
        data class AgentFailed(override val detail: String) : Failure
    }

    /** Which failure a transport error is */
    fun failure(error: Throwable): Failure {
        val detail = error.message ?: error.toString()
        val text = (detail + " " + error.toString()).lowercase()
        val refused = text.contains("authentication") || text.contains("auth fail") ||
            text.contains("allauthenticationoptionsfailed")
        return if (refused) Failure.KeyRefused(detail) else Failure.Unreachable(detail)
    }

    fun services(reported: List<Pair<String, List<String>>>): Set<ServiceID> =
        AgentServiceMapping.serviceIDsForServices(reported)

    fun name(hostname: String, fallback: String): String =
        hostname.trim().ifEmpty { fallback.trim() }

    /** The domain to save */
    fun domain(reported: List<String>): String = reported.firstOrNull()?.trim().orEmpty()
}
