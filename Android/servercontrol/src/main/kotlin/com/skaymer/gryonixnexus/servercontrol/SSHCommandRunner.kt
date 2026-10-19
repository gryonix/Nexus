package com.skaymer.gryonixnexus.servercontrol

import kotlin.time.Duration
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow

/** Which machine executes a command */
data class SSHHostID(val kind: Kind) {
    sealed class Kind {
        data class Slot(val slot: DeploymentNode.LegacySlot) : Kind()

        /** Any machine added after nodes had identities of their own */
        data class Node(val id: String) : Kind()
    }

    /** The slot this host occupies, when it has one */
    val slot: DeploymentNode.LegacySlot?
        get() = (kind as? Kind.Slot)?.slot

    companion object {
        val VPS = SSHHostID(Kind.Slot(DeploymentNode.LegacySlot.VPS))

        /** Scenario B's services machine, reached through the entry machine */
        val HOME = SSHHostID(Kind.Slot(DeploymentNode.LegacySlot.HOME))

        fun node(id: String): SSHHostID = SSHHostID(Kind.Node(id))
    }
}

/** Outcome of a completed remote command */
data class ExecResult(
    /** Null when the channel closed without delivering an exit status */
    val exitCode: Int?,
    val stdout: String,
    val stderr: String,
) {
    val succeeded: Boolean get() = exitCode == 0
}

/** A piece of live output from a streaming command */
sealed class ExecChunk {
    abstract val text: String

    data class Stdout(override val text: String) : ExecChunk()

    data class Stderr(override val text: String) : ExecChunk()
}

/** The single seam between dashboard logic and the SSH implementation */
interface SSHCommandRunner {
    /** Runs a command to completion */
    suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult

    fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk>

    /** Sends a command without awaiting its exit status */
    suspend fun fireAndForget(command: String, host: SSHHostID)

    /** Runs a command with [secret] on stdin, never in argv */
    suspend fun run(command: String, secret: String, host: SSHHostID, timeout: Duration): ExecResult =
        throw ServerControlError.NotConfigured("this connection cannot pass a secret privately")

    suspend fun disconnect()
}

/** Injected clock for poll loops so tests run instantly */
interface SleepProvider {
    suspend fun sleep(duration: Duration)
}

object CoroutineSleeper : SleepProvider {
    override suspend fun sleep(duration: Duration) = delay(duration)
}
