package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.agentclient.AgentByteStream
import java.io.InputStream
import java.io.OutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** An [AgentByteStream] over an SSH exec channel's stdin/stdout */
class ExecByteStream(
    private val stdin: OutputStream,
    private val stdout: InputStream,
    private val stderr: InputStream,
) : AgentByteStream {
    private val buffer = ByteArray(32 * 1024)

    private val stderrLog = StringBuilder()

    /** stderr as text, trimmed; empty when the command said nothing */
    val stderrText: String get() = stderrLog.toString().trim()

    override suspend fun write(data: ByteArray) = withContext(Dispatchers.IO) {
        stdin.write(data)
        stdin.flush()
    }

    override suspend fun read(): ByteArray = withContext(Dispatchers.IO) {
        drainStderr()
        val n = stdout.read(buffer)
        if (n <= 0) {
            drainStderr()
            ByteArray(0)
        } else {
            buffer.copyOfRange(0, n)
        }
    }

    private fun drainStderr() {
        while (stderr.available() > 0 && stderrLog.length < STDERR_LIMIT) {
            val n = stderr.read(buffer, 0, minOf(buffer.size, STDERR_LIMIT - stderrLog.length))
            if (n <= 0) return
            stderrLog.append(String(buffer, 0, n))
        }
    }

    override suspend fun close() {
    }

    private companion object {
        const val STDERR_LIMIT = 2048
    }
}
