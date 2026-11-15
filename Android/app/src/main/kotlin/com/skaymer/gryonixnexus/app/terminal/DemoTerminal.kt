package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import com.skaymer.gryonixnexus.transport.TerminalEvent
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.receiveAsFlow

/** Pretend shell of a demo server */
class DemoShell(user: String, private val host: String) {
    private val user = user.ifEmpty { "server-user" }
    private val line = StringBuilder()

    val banner: String
        get() = "Welcome to Debian GNU/Linux 13 (demo)\r\n" +
            "This is an example server: commands are not run anywhere.\r\n" +
            "Try: uptime, df -h, docker ps, free -h, help\r\n\r\n" + prompt

    private val prompt: String get() = "$user@${host.substringBefore('.')}:~$ "

    /** What the screen shows for the typed bytes */
    fun input(bytes: ByteArray): String = buildString {
        for (byte in bytes) {
            when (val code = byte.toInt() and 0xFF) {
                13, 10 -> {
                    append("\r\n").append(answer(line.toString().trim())).append(prompt)
                    line.clear()
                }
                127, 8 -> if (line.isNotEmpty()) {
                    line.setLength(line.length - 1)
                    append("\b \b")
                }
                3 -> {
                    line.clear()
                    append("^C\r\n").append(prompt)
                }
                in 32..126 -> {
                    line.append(code.toChar())
                    append(code.toChar())
                }
            }
        }
    }

    private fun answer(command: String): String = when (command) {
        "" -> ""
        "help" -> "uptime  df -h  free -h  docker ps  whoami  ls\r\n"
        "whoami" -> "server-user\r\n"
        "ls" -> "backups  docker-compose  notes.txt\r\n"
        "uptime" -> " 10:42:07 up 47 days,  3:12,  1 user,  load average: 0.31, 0.28, 0.25\r\n"
        "free -h" -> "               total        used        free\r\nMem:           7.8Gi       5.0Gi       2.8Gi\r\n"
        "df -h" -> "Filesystem      Size  Used Avail Use% Mounted on\r\n/dev/sda1       160G   83G   77G  52% /\r\n"
        "docker ps" -> "CONTAINER ID   IMAGE                       STATUS\r\n" +
            "3f2a9c1d0e4b   vaultwarden/server:latest   Up 12 days (healthy)\r\n" +
            "8b7e6d5c4a3f   nextcloud:30-apache         Up 12 days\r\n"
        else -> "demo: $command: runs only on your own server\r\n"
    }
}

/** The demo shell behind the terminal's transport */
class DemoTerminalTransport(user: String, host: String) : TerminalTransport {
    private val shell = DemoShell(user, host)
    private val events = Channel<TerminalEvent>(Channel.UNLIMITED)
    override val output: Flow<TerminalEvent> = events.receiveAsFlow()

    override suspend fun start(columns: Int, rows: Int) {
        events.send(TerminalEvent.Output(shell.banner.toByteArray()))
    }

    override suspend fun send(data: ByteArray) {
        events.send(TerminalEvent.Output(shell.input(data).toByteArray()))
    }

    override suspend fun resize(columns: Int, rows: Int) = Unit

    override suspend fun close() {
        events.close()
    }
}

/** Refuses to open a real server's shell without a license */
class LockedTerminalTransport(private val deploymentID: String) : TerminalTransport {
    override val output: Flow<TerminalEvent> = emptyFlow()
    override suspend fun start(columns: Int, rows: Int) = LicenseGate.check(deploymentID)
    override suspend fun send(data: ByteArray) = Unit
    override suspend fun resize(columns: Int, rows: Int) = Unit
    override suspend fun close() = Unit
}
