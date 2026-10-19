package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.SH
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.isActive

class SetupInstaller(
    private val runner: SSHCommandRunner,
    private val host: SSHHostID = SSHHostID.VPS,
    private val username: String = "root",
    private val runTimeout: Duration = 3600.seconds,
    private val uploadTimeout: Duration = 30.seconds,
    private val sleeper: SleepProvider = CoroutineSleeper,
) {
    fun install(
        script: String,
        fileName: String,
        skipDNSCheck: Boolean = false,
        skipServices: Boolean = false,
    ): Flow<SetupEvent> = flow {
        var detached = false
        var stillRunning = false
        try {
            upload(script, fileName)
            start(fileName, skipDNSCheck, skipServices)
            detached = true
            follow(fileName) { emit(it) }
        } catch (error: Throwable) {
            stillRunning = detached &&
                (error is kotlinx.coroutines.CancellationException || error is ServerControlError.InstallUnfollowable)
            throw error
        } finally {
            if (!stillRunning) wipe(fileName)
        }
    }

    // ----------------------------------------------------------------- Steps

    /** The script carries keys, so it travels on stdin */
    private suspend fun upload(script: String, fileName: String) {
        val file = ShellQuoting.singleQuoted(fileName)
        val command = "umask 077 && rm -f $file && cat > $file"
        val result = runner.run(command, script, host, uploadTimeout)
        if (!result.succeeded) {
            throw ServerControlError.CommandFailed(command, result.exitCode, OutputTail.tail(result.stderr))
        }
    }

    private suspend fun start(fileName: String, skipDNSCheck: Boolean, skipServices: Boolean = false) {
        val file = ShellQuoting.singleQuoted(fileName)
        val log = ShellQuoting.singleQuoted(logName(fileName))
        val envVars = buildList {
            if (skipDNSCheck) add("GRYONIXNEXUS_SKIP_DNS_CHECK=1")
            if (skipServices) add("GRYONIXNEXUS_SKIP_SERVICES=1")
        }
        val interpreter = if (envVars.isEmpty()) "bash" else "env ${envVars.joinToString(" ")} bash"
        val invocation = if (username == "root") "$interpreter $file" else "sudo -n $interpreter $file"
        val payload = "$invocation >> $log 2>&1; " +
            "echo \"${SetupProgressParser.EXIT_MARKER}${SH}?\" >> $log"
        val detach = "command -v setsid >/dev/null 2>&1 && DETACH=setsid || DETACH="
        run(
            "(umask 077 && rm -f $log && : > $log) && $detach; " +
                "${SH}DETACH sh -c ${ShellQuoting.singleQuoted(payload)} " +
                "</dev/null >/dev/null 2>&1 &",
        )
    }

    /** Streams the detached run's log, re-attaching across dropped sessions */
    private suspend fun follow(fileName: String, emit: suspend (SetupEvent) -> Unit) {
        val parser = SetupProgressParser()
        var tail = ""
        var linesConsumed = 0
        var attempt = 0

        while (true) {
            val command = followCommand(fileName, linesConsumed + 1)
            val deliveredBefore = linesConsumed
            try {
                runner.stream(command, host, runTimeout).collect { chunk ->
                    linesConsumed += chunk.text.count { it == '\n' }
                    tail = OutputTail.tail(tail + chunk.text)
                    parser.consume(chunk.text).forEach { emit(it) }
                }
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (_: Throwable) {
            }

            if (parser.exitCode != null) {
                parser.finish().forEach { emit(it) }
                break
            }

            if (linesConsumed > deliveredBefore) attempt = 0

            if (attempt >= MAX_REATTACHES || !currentCoroutineContext().isActive) {
                throw ServerControlError.InstallUnfollowable
            }
            attempt += 1
            parser.discardPartialLine()
            emit(SetupEvent.Reconnecting(attempt))
            runner.disconnect()
            runCatching { sleeper.sleep(minOf(5 * attempt, 20).seconds) }
        }

        val code = parser.exitCode
        if (code != null && code != 0) {
            throw ServerControlError.CommandFailed("install", code, OutputTail.tail(tail))
        }
        if (!parser.sawDone) {
            throw ServerControlError.CommandFailed("install", null, OutputTail.tail(tail))
        }
    }

    /** Best-effort cleanup of both the script and any staging leftover */
    private suspend fun wipe(fileName: String) {
        val file = ShellQuoting.singleQuoted(fileName)
        val staging = ShellQuoting.singleQuoted("$fileName.b64")
        val log = ShellQuoting.singleQuoted(logName(fileName))
        runCatching { runner.run("rm -f $staging $file $log", host, uploadTimeout) }
    }

    private suspend fun run(command: String): ExecResult {
        val result = runner.run(command, host, uploadTimeout)
        if (!result.succeeded) {
            throw ServerControlError.CommandFailed(
                command,
                result.exitCode,
                OutputTail.tail(result.stderr),
            )
        }
        return result
    }

    companion object {
        private const val MAX_REATTACHES = 5

        internal fun logName(fileName: String): String = "$fileName.log"

        internal fun followCommand(fileName: String, fromLine: Int): String {
            val log = ShellQuoting.singleQuoted(logName(fileName))
            val script = """
                n=$fromLine
                while :; do
                  tot=${SH}(wc -l < $log 2>/dev/null || echo 0)
                  if [ "${SH}tot" -ge "${SH}n" ]; then sed -n "${SH}{n},${SH}{tot}p" $log; n=${SH}((tot + 1)); fi
                  if [ "${SH}tot" -ge 1 ] && sed -n "${SH}{tot}p" $log | grep -q "^${SetupProgressParser.EXIT_MARKER}"; then exit 0; fi
                  sleep 1
                done
            """.trimIndent()
            return "sh -c ${ShellQuoting.singleQuoted(script)}"
        }
    }
}
