package com.skaymer.gryonixnexus.servercontrol

import kotlin.time.Duration
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

open class FakeSSHCommandRunner : SSHCommandRunner {
    enum class CallKind { RUN, STREAM, FIRE_AND_FORGET }

    data class Call(val kind: CallKind, val command: String, val host: SSHHostID)

    private class Stub(
        /** Substring the incoming command must contain; "" matches anything */
        val match: String,
        val result: Result<ExecResult>,
    )

    private val stubs = ArrayDeque<Stub>()
    private val recorded = mutableListOf<Call>()

    val calls: List<Call> get() = recorded

    /** Fallback when the stub queue is exhausted */
    var defaultResult = ExecResult(exitCode = 0, stdout = "", stderr = "")

    fun stub(match: String, stdout: String = "", exitCode: Int = 0, stderr: String = "") {
        stubs.addLast(Stub(match, Result.success(ExecResult(exitCode, stdout, stderr))))
    }

    fun stubFailure(match: String, error: Throwable) {
        stubs.addLast(Stub(match, Result.failure(error)))
    }

    private fun record(kind: CallKind, command: String, host: SSHHostID) {
        recorded += Call(kind, command, host)
    }

    private fun nextResult(command: String): ExecResult {
        val stub = stubs.removeFirstOrNull() ?: return defaultResult
        check(stub.match.isEmpty() || command.contains(stub.match)) {
            "expected command containing '${stub.match}', got '$command'"
        }
        return stub.result.getOrThrow()
    }

    private var detached: ExecResult? = null

    /** Secrets handed over on stdin, in order */
    val fed = mutableListOf<String>()

    override suspend fun run(command: String, secret: String, host: SSHHostID, timeout: Duration): ExecResult {
        fed += secret
        return run(command, host, timeout)
    }

    override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult {
        record(CallKind.RUN, command, host)
        val result = nextResult(command)
        if (command.contains(DetachedJobs.EXIT_MARKER) && command.contains("\$DETACH")) {
            detached = result
            return ExecResult(exitCode = 0, stdout = "", stderr = "")
        }
        return result
    }

    override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> {
        record(CallKind.STREAM, command, host)
        val pending = if (command.contains(DetachedJobs.EXIT_MARKER)) detached else null
        if (pending != null) {
            detached = null
            return flow {
                if (pending.stdout.isNotEmpty()) emit(ExecChunk.Stdout(pending.stdout))
                if (pending.stderr.isNotEmpty()) emit(ExecChunk.Stderr(pending.stderr))
                emit(ExecChunk.Stdout("\n${DetachedJobs.EXIT_MARKER}${pending.exitCode}\n"))
            }
        }
        return flow {
            val result = nextResult(command)
            if (result.stdout.isNotEmpty()) emit(ExecChunk.Stdout(result.stdout))
            if (result.stderr.isNotEmpty()) emit(ExecChunk.Stderr(result.stderr))
        }
    }

    override suspend fun fireAndForget(command: String, host: SSHHostID) {
        record(CallKind.FIRE_AND_FORGET, command, host)
        nextResult(command)
    }

    var disconnects = 0
        private set

    override suspend fun disconnect() {
        disconnects++
    }
}

/** Counts sleeps instead of sleeping so poll loops run instantly */
class FakeSleeper : SleepProvider {
    private val recorded = mutableListOf<Duration>()

    val sleeps: List<Duration> get() = recorded

    override suspend fun sleep(duration: Duration) {
        recorded += duration
    }
}
