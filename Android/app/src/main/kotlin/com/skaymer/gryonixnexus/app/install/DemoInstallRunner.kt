package com.skaymer.gryonixnexus.app.install

import com.skaymer.gryonixnexus.recipe.SetupMarkers
import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.SetupProgressParser
import com.skaymer.gryonixnexus.servercontrol.SudoAccess
import kotlin.time.Duration
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/** The machine an unlicensed installation runs on */
class DemoInstallRunner(
    private val services: List<String>,
    private val domain: String,
) : SSHCommandRunner {
    private var script = ""

    override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult {
        delay(LATENCY)
        if (command.contains(PROBE_TOKEN)) {
            val output = "$PROBE_TOKEN\n${SetupMarkers.DISTRIBUTION}:debian:\n${SudoAccess.READY_TOKEN}\n"
            return ExecResult(0, output, "")
        }
        return ExecResult(0, "", "")
    }

    override suspend fun run(command: String, secret: String, host: SSHHostID, timeout: Duration): ExecResult {
        delay(LATENCY)
        script = secret
        return ExecResult(0, "", "")
    }

    override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> = flow {
        if (!command.contains(SetupProgressParser.EXIT_MARKER)) return@flow
        for (line in lines(script, services, domain)) {
            delay(line.delay)
            emit(ExecChunk.Stdout(line.text + "\n"))
        }
    }

    override suspend fun fireAndForget(command: String, host: SSHHostID) {}

    override suspend fun disconnect() {}

    private class Line(val text: String, val delay: Long = 220)

    private companion object {
        const val LATENCY = 140L
        const val PROBE_TOKEN = "GRYONIXNEXUS_PING"
        val FALLBACK_STAGES = listOf(
            "Reading the distribution",
            "Installing packages",
            "Firewall (nftables, default-deny)",
            "Web server and certificates",
            "Services",
        )

        fun stages(script: String): List<String> {
            val found = mutableListOf<String>()
            for (raw in script.lines()) {
                val line = raw.trim()
                if (!line.startsWith("log \"") || !line.endsWith("\"")) continue
                val text = line.drop(5).dropLast(1)
                if (text.isEmpty() || text.contains("$") || text in found) continue
                found.add(text)
            }
            return found.ifEmpty { FALLBACK_STAGES }
        }

        fun lines(script: String, services: List<String>, domain: String): List<Line> {
            val steps = stages(script)
            val out = mutableListOf(Line("==> Reading the machine", 500))
            steps.forEachIndexed { index, stage ->
                out.add(Line("${SetupMarkers.STEP} ${index + 1}/${steps.size + 1}", 60))
                out.add(Line("==> $stage", 520))
                out.add(Line("  ok", 240))
            }
            out.add(Line("${SetupMarkers.STEP} ${steps.size + 1}/${steps.size + 1}", 60))
            out.addAll(report(services, domain))
            out.add(Line(SetupMarkers.DONE, 200))
            out.add(Line("${SetupProgressParser.EXIT_MARKER}0", 60))
            return out
        }

        fun report(services: List<String>, domain: String): List<Line> = listOf(
            Line(SetupMarkers.REPORT_BEGIN, 300),
            Line("GRYONIXNEXUS_REPORT", 40),
            Line("Domain: $domain", 40),
            Line("Services: ${services.joinToString(", ")}", 40),
            Line("Admin user: admin@$domain", 40),
            Line("Nothing here touched a real machine — this server is emulated.", 40),
            Line(SetupMarkers.REPORT_END, 60),
        )
    }
}
