package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.recipe.AgentBootstrapSections
import com.skaymer.gryonixnexus.servercontrol.RemoteFileBrowser
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import com.skaymer.gryonixnexus.servercontrol.DetachedAgentBuild
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration.Companion.seconds

object AgentBootstrapOperations {
    /** The archive this build carries, as bytes */
    fun interface Sources {
        fun archive(): ByteArray
    }

    fun interface Reporter {
        fun report(line: String)
    }

    suspend fun install(
        runner: SSHCommandRunner,
        /** The file half of the same session */
        files: RemoteFileBrowser,
        host: SSHHostID,
        sources: Sources,
        onPhase: Reporter,
        onOutput: Reporter,
        reinstall: Boolean = false,
    ) {
        val home = files.homeDirectory(host)
        val build = DetachedAgentBuild(home)
        if (build.isRunning(runner, host)) {
            onPhase.report(FOLLOWING)
            finish(build, runner, host, onPhase, onOutput)
            return
        }
        if (reinstall) {
            val marker = "$home/${AgentBootstrapSections.REINSTALL_MARKER_NAME}"
            runner.run(": > ${singleQuoted(marker)}", host, 20.seconds)
        }
        val remoteArchive = "$home/${AgentBootstrapSections.ARCHIVE_NAME}"
        upload(sources, files, host, remoteArchive, onPhase) { failure ->
            "Could not write $remoteArchive on the server: ${failure.message ?: failure}"
        }
        try {
            finish(build, runner, host, onPhase, onOutput)
        } catch (missing: WrapperMissing) {
            onPhase.report(PREPARING)
            installWrapper(runner, files, host, remoteArchive, home)
            finish(build, runner, host, onPhase, onOutput)
        } catch (mismatch: ArchiveElsewhere) {
            onPhase.report(RELOCATING)
            onOutput.report("The server reads ${mismatch.expected}; the upload went to $remoteArchive.")
            upload(sources, files, host, mismatch.expected, onPhase) {
                "The server looks for the agent sources in ${mismatch.expected}, and this " +
                    "account cannot write there. Connect as a user that can, or re-run the " +
                    "installation to refresh the server's wrapper."
            }
            finish(build, runner, host, onPhase, onOutput)
        }
    }

    private suspend fun upload(
        sources: Sources,
        files: RemoteFileBrowser,
        host: SSHHostID,
        path: String,
        onPhase: Reporter,
        refusal: (Exception) -> String,
    ) {
        onPhase.report(SENDING)
        try {
            files.uploadFile(sources.archive(), path, host)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            throw ServerControlError.NotConfigured(refusal(failure))
        }
    }

    private suspend fun finish(
        build: DetachedAgentBuild,
        runner: SSHCommandRunner,
        host: SSHHostID,
        onPhase: Reporter,
        onOutput: Reporter,
    ) {
        onPhase.report(BUILDING)
        if (!build.isRunning(runner, host)) {
            runner.run(build.startCommand(null, AgentBootstrapSections.SCRIPT_PATH), host, 60.seconds)
        }
        val outcome = build.follow(
            runner, host, onOutput::report,
            onReconnect = { error ->
                onPhase.report(RECONNECTING)
                onOutput.report("Connection dropped: ${error.message ?: error::class.simpleName}")
            },
            onReconnected = { onPhase.report(RECONNECTED) },
        )
        if (outcome.exitCode == 0) return
        expectedArchivePath(outcome.transcript)?.let { throw ArchiveElsewhere(it) }
        if (wrapperIsMissing(outcome.transcript)) throw WrapperMissing()
        val tail = outcome.transcript.lines().filter { it.isNotBlank() }.takeLast(8).joinToString("\n")
        throw ServerControlError.NotConfigured(
            "The agent did not build on this server: ${tail.ifEmpty { "the build stopped without saying why" }}",
        )
    }

    /** Raised when the wrapper looked somewhere else for the archive */
    private class ArchiveElsewhere(val expected: String) : Exception()

    private class WrapperMissing : Exception()

    private suspend fun installWrapper(
        runner: SSHCommandRunner,
        files: RemoteFileBrowser,
        host: SSHHostID,
        archivePath: String,
        home: String,
    ) {
        val staged = "$home/.gryonixnexus-agent-bootstrap.sh"
        val script = AgentBootstrapSections.wrapperScript(archivePath) + "\n"
        files.uploadFile(script.toByteArray(), staged, host)
        val command = "sudo -n install -o root -g root -m 700 " +
            "${singleQuoted(staged)} ${singleQuoted(AgentBootstrapSections.SCRIPT_PATH)}"
        val result = runCatching { runner.run(command, host, 60.seconds) }.getOrNull()
        runCatching { runner.run("rm -f ${singleQuoted(staged)}", host, 30.seconds) }
        if (result == null || result.exitCode != 0) {
            throw ServerControlError.NotConfigured(
                "This server has never been set up by the app, so it has no agent installer, and " +
                    "this account cannot create one in ${AgentBootstrapSections.SCRIPT_PATH}. " +
                    "Connect as a user that can run sudo, or install the server from the app first."
            )
        }
    }

    /** Whether the server answered "there is no such wrapper" */
    fun wrapperIsMissing(output: String): Boolean {
        if (!output.contains(AgentBootstrapSections.SCRIPT_PATH)) return false
        return output.contains("command not found") ||
            output.contains("No such file or directory")
    }

    fun expectedArchivePath(output: String): String? {
        for (line in output.split("\n")) {
            val open = line.indexOf(MARKER)
            if (open < 0) continue
            val from = open + MARKER.length
            val close = line.indexOf(')', from)
            if (close < 0) continue
            val path = line.substring(from, close)
            if (!path.startsWith("/") || path.contains(" ")) continue
            return path
        }
        return null
    }

    private fun singleQuoted(value: String): String = "'" + value.replace("'", "'\\''") + "'"

    private const val MARKER = "no agent sources uploaded ("

    const val SENDING = "Sending the agent sources…"
    const val BUILDING = "The server is building the agent on its own. You can minimise the app: " +
        "when you come back, it picks up the build where it is."
    const val FOLLOWING = "The server is already building the agent. Following it…"
    const val RECONNECTING = "The connection dropped; the server keeps building. Reconnecting…"
    const val RECONNECTED = "Connected again. The server is still building the agent."
    const val PREPARING = "Preparing the server…"
    const val RELOCATING = "Putting the sources where the server expects them…"
}
