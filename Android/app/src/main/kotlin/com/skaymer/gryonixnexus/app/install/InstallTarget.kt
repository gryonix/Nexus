package com.skaymer.gryonixnexus.app.install

import com.skaymer.gryonixnexus.app.access.SudoProblem
import com.skaymer.gryonixnexus.catalog.storage.ServerHardware
import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.recipe.SetupMarkers
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode

data class InstallTarget(
    val kind: Kind,
    val script: Artifact,
    val slot: DeploymentNode.LegacySlot,
    val address: String,
    val port: Int = 22,
    val username: String = "root",
    val secret: Secret = Secret.AppKey,
    val connection: Connection = Connection.Unchecked,
    /** Hardware read during the connection check */
    val hardware: ServerHardware? = null,
    val storage: StorageChoice = StorageChoice(),
    val swap: Swap = Swap.Idle,
) {
    /** Where adding swap stands */
    sealed interface Swap {
        data object Idle : Swap
        data object Adding : Swap
        data class Failed(val reason: String) : Swap
    }

    enum class Kind { SINGLE, VPS, HOME }

    sealed interface Secret {
        data object AppKey : Secret

        data class Password(val value: String) : Secret
    }

    sealed interface Connection {
        data object Unchecked : Connection
        data object Checking : Connection
        data object Ok : Connection

        /** Signed in, but sudo still asks for a password */
        data class NeedsSudoPassword(val problem: SudoProblem? = null) : Connection
        data object NotAdministrator : Connection
        data class Failed(val reason: String) : Connection
    }

    val isReady: Boolean
        get() = connection is Connection.Ok &&
            (secret !is Secret.Password || secret.value.isNotEmpty()) && storageIsReady

    val expectedDistribution: String?
        get() = script.contents
            .lineSequence()
            .take(10)
            .firstOrNull { "${SetupMarkers.DISTRIBUTION}:" in it }
            ?.substringAfterLast(':')
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
}
