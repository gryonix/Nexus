package com.skaymer.gryonixnexus.app.servers.demo

import com.skaymer.gryonixnexus.servercontrol.DetachedJobs
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.RemoteFileBrowser
import com.skaymer.gryonixnexus.servercontrol.RemoteFileEntry
import com.skaymer.gryonixnexus.servercontrol.RemotePath
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import java.time.Instant
import kotlin.time.Duration
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/** The machine behind a demo server */
class DemoCommandRunner(deployment: Deployment) : SSHCommandRunner, RemoteFileBrowser {
    private val machine = DemoAgentMachine(deployment)
    private var pending: String? = null

    override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult {
        delay(LATENCY)
        val text = DemoFleetCommands.respond(command, host, machine)
        if (DetachedJobs.EXIT_MARKER in command && "\$DETACH" in command) {
            pending = text
            return ExecResult(exitCode = 0, stdout = "", stderr = "")
        }
        return ExecResult(exitCode = 0, stdout = text, stderr = "")
    }

    override suspend fun run(command: String, secret: String, host: SSHHostID, timeout: Duration): ExecResult =
        run(command, host, timeout)

    override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> = flow {
        delay(LATENCY)
        val replay = pending.takeIf { DetachedJobs.EXIT_MARKER in command }
        if (replay != null) {
            pending = null
            emit(ExecChunk.Stdout(replay))
            emit(ExecChunk.Stdout("\n${DetachedJobs.EXIT_MARKER}0\n"))
            return@flow
        }
        emit(ExecChunk.Stdout(DemoFleetCommands.respond(command, host, machine)))
    }

    override suspend fun fireAndForget(command: String, host: SSHHostID) {
        DemoFleetCommands.respond(command, host, machine)
    }

    override suspend fun disconnect() = Unit

    // Files

    override suspend fun homeDirectory(host: SSHHostID): String = HOME

    override suspend fun listDirectory(path: String, host: SSHHostID): List<RemoteFileEntry> {
        delay(LATENCY)
        val now = Instant.now()
        return when (path) {
            HOME -> listOf(
                entry("backups", path, RemoteFileEntry.Kind.DIRECTORY, null, now.minusSeconds(3_600)),
                entry("docker", path, RemoteFileEntry.Kind.DIRECTORY, null, now.minusSeconds(86_400)),
                entry("install-report.txt", path, RemoteFileEntry.Kind.FILE, 2_048, now.minusSeconds(604_800)),
            )
            "$HOME/backups" -> listOf(
                entry("vaultwarden-2026-08-16.tar.gz", path, RemoteFileEntry.Kind.FILE, 4_812_544, now.minusSeconds(7_200)),
                entry("nextcloud-2026-08-16.tar.gz", path, RemoteFileEntry.Kind.FILE, 918_235_136, now.minusSeconds(9_000)),
            )
            else -> emptyList()
        }
    }

    override suspend fun downloadFile(path: String, host: SSHHostID, maxBytes: Long): ByteArray {
        delay(LATENCY)
        return DemoFleetCommands.INSTALL_REPORT.toByteArray()
    }

    override suspend fun uploadFile(data: ByteArray, path: String, host: SSHHostID) = delay(LATENCY)

    override suspend fun deleteFile(entry: RemoteFileEntry, host: SSHHostID) = delay(LATENCY)

    private fun entry(name: String, directory: String, kind: RemoteFileEntry.Kind, size: Long?, modified: Instant) =
        RemoteFileEntry(name = name, path = RemotePath.join(directory, name), kind = kind, size = size, modified = modified)

    private companion object {
        const val LATENCY = 220L
        const val HOME = "/home/server-user"
    }
}
