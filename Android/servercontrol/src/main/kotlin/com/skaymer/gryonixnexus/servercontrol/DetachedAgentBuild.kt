package com.skaymer.gryonixnexus.servercontrol

import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.delay

class DetachedAgentBuild(val home: String, private val retryDelay: Duration = 5.seconds) {
    val logPath: String get() = "$home/.gryonixnexus-agent-build.log"
    val pidPath: String get() = "$home/.gryonixnexus-agent-build.pid"

    data class Outcome(val exitCode: Int, val transcript: String)

    val runningCheck: String
        get() = bash("kill -0 \"\$(cat ${q(pidPath)} 2>/dev/null)\" 2>/dev/null && echo $RUNNING_MARKER || true")

    /** setsid + nohup: the build survives the SSH session ending */
    fun startCommand(fetchScript: String?, wrapper: String): String {
        val fetch = fetchScript?.let { "bash ${q(it)}; R=\$?; rm -f ${q(it)}; [ \"\$R\" = 0 ] && " }.orEmpty()
        val job = "echo \$\$ > ${q(pidPath)}; ${fetch}sudo -n $wrapper; echo $EXIT_MARKER\$?"
        return bash(
            "rm -f ${q(pidPath)}; : > ${q(logPath)}; " +
                "setsid nohup bash -c ${q(job)} >> ${q(logPath)} 2>&1 < /dev/null & " +
                "for i in \$(seq 50); do [ -s ${q(pidPath)} ] && break; sleep 0.1; done; echo started",
        )
    }

    fun followCommand(line: Int): String = bash(
        "PID=\"\$(cat ${q(pidPath)} 2>/dev/null)\"; " +
            "if [ -n \"\$PID\" ] && kill -0 \"\$PID\" 2>/dev/null; " +
            "then exec tail -n +$line --pid=\"\$PID\" -F ${q(logPath)} 2>/dev/null; " +
            "else exec tail -n +$line ${q(logPath)} 2>/dev/null; fi",
    )

    suspend fun isRunning(runner: SSHCommandRunner, host: SSHHostID): Boolean =
        RUNNING_MARKER in runner.run(runningCheck, host, 30.seconds).stdout

    suspend fun follow(
        runner: SSHCommandRunner,
        host: SSHHostID,
        onOutput: (String) -> Unit,
        onReconnect: (Exception) -> Unit,
        onReconnected: () -> Unit = {},
    ): Outcome {
        val reader = BuildLogReader()
        var failures = 0
        var dropped = false
        while (true) {
            try {
                val back = if (dropped) onReconnected else ({})
                dropped = false
                readOnce(reader, runner, host, onOutput, back)?.let { return it }
                delay(1.seconds)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                failures += 1
                if (failures > RECONNECT_ATTEMPTS) throw failure
                dropped = true
                onReconnect(failure)
                delay(retryDelay)
            }
            reader.dropPartial()
        }
    }

    private suspend fun readOnce(
        reader: BuildLogReader,
        runner: SSHCommandRunner,
        host: SSHHostID,
        onOutput: (String) -> Unit,
        onFirstLine: () -> Unit,
    ): Outcome? {
        var done: Outcome? = null
        var first = true
        runner.stream(followCommand(reader.linesSeen + 1), host, 3.hours).collect { chunk ->
            if (chunk !is ExecChunk.Stdout || done != null) return@collect
            if (first) { first = false; onFirstLine() }
            reader.feed(chunk.text).forEach(onOutput)
            reader.exitCode?.let { done = Outcome(it, reader.transcript) }
        }
        done?.let { return it }
        if (isRunning(runner, host)) return null
        return Outcome(-1, reader.transcript)
    }

    private fun q(value: String) = ShellQuoting.singleQuoted(value)

    companion object {
        const val EXIT_MARKER = "GRYONIXNEXUS_AGENT_BUILD_EXIT="
        const val RUNNING_MARKER = "GRYONIXNEXUS_AGENT_BUILD_RUNNING"
        const val RECONNECT_ATTEMPTS = 60

        /** Everything runs under bash, whatever the login shell is */
        fun bash(script: String) = "bash -c ${ShellQuoting.singleQuoted(script)}"
    }
}

/** Splits the log into lines and finds the exit marker */
class BuildLogReader {
    var linesSeen = 0
        private set
    var exitCode: Int? = null
        private set
    private val text = StringBuilder()
    val transcript: String get() = text.toString()
    private var partial = ""

    fun feed(raw: String): List<String> {
        partial = (partial + raw).replace("\r\n", "\n")
        val lines = mutableListOf<String>()
        while (true) {
            val newline = partial.indexOf('\n').takeIf { it >= 0 } ?: break
            val line = partial.substring(0, newline)
            partial = partial.substring(newline + 1)
            linesSeen += 1
            if (line.startsWith(DetachedAgentBuild.EXIT_MARKER)) {
                exitCode = line.removePrefix(DetachedAgentBuild.EXIT_MARKER).trim().toIntOrNull() ?: -1
                continue
            }
            val trimmed = line.trim()
            if (trimmed.isEmpty()) continue
            text.append(trimmed).append('\n')
            lines += trimmed
        }
        return lines
    }

    /** A cut line is read again from its start */
    fun dropPartial() {
        partial = ""
    }
}
