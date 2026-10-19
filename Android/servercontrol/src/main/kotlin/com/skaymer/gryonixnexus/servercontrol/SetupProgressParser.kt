package com.skaymer.gryonixnexus.servercontrol

sealed class SetupEvent {
    /** Progress marker: the script entered step [index] of [total] */
    data class Step(val index: Int, val total: Int) : SetupEvent()

    data class Stage(val title: String) : SetupEvent()

    data class Line(val text: String) : SetupEvent()

    data class Report(val text: String) : SetupEvent()

    data object Done : SetupEvent()

    data class Reconnecting(val attempt: Int) : SetupEvent()
}

class SetupProgressParser {
    private object Marker {
        const val STEP = "GRYONIXNEXUS_STEP "
        const val REPORT_BEGIN = "GRYONIXNEXUS_REPORT_BEGIN"
        const val REPORT_END = "GRYONIXNEXUS_REPORT_END"
        const val DONE = "GRYONIXNEXUS_DONE"
    }

    private var buffer = StringBuilder()
    private var reportLines: MutableList<String>? = null

    /** True once the DONE marker has been seen */
    var sawDone: Boolean = false
        private set

    /** Last observed progress, for UIs that attach mid-stream */
    var currentStep: SetupEvent.Step? = null
        private set

    var exitCode: Int? = null
        private set

    fun consume(text: String): List<SetupEvent> {
        buffer.append(text)
        val events = mutableListOf<SetupEvent>()
        while (true) {
            val newline = buffer.indexOf("\n")
            if (newline < 0) break
            val line = buffer.substring(0, newline)
            buffer.delete(0, newline + 1)
            events += parse(line)
        }
        return events
    }

    /** Drops a buffered partial line before re-attaching to a log */
    fun discardPartialLine() {
        buffer = StringBuilder()
    }

    fun finish(): List<SetupEvent> {
        if (buffer.isEmpty()) return emptyList()
        val line = buffer.toString()
        buffer = StringBuilder()
        return parse(line)
    }

    private fun parse(raw: String): List<SetupEvent> {
        // Package managers redraw progress with ANSI codes and bare CRs.
        val line = ANSIStripper.strip(raw)

        if (line.startsWith(Marker.STEP)) {
            val parts = line.removePrefix(Marker.STEP).split("/")
            if (parts.size == 2) {
                val index = parts[0].toIntOrNull()
                val total = parts[1].toIntOrNull()
                if (index != null && total != null) {
                    val step = SetupEvent.Step(index, total)
                    currentStep = step
                    return listOf(step)
                }
            }
        }
        if (line.startsWith(EXIT_MARKER)) {
            exitCode = line.removePrefix(EXIT_MARKER).trim().toIntOrNull() ?: 0
            return emptyList()
        }
        when (line) {
            Marker.REPORT_BEGIN -> {
                reportLines = mutableListOf()
                return emptyList()
            }
            Marker.REPORT_END -> {
                val report = (reportLines ?: emptyList<String>()).joinToString("\n")
                reportLines = null
                return listOf(SetupEvent.Report(report))
            }
            Marker.DONE -> {
                sawDone = true
                return listOf(SetupEvent.Done)
            }
        }

        reportLines?.add(line)
        if (line.startsWith("==> ")) {
            val title = line.removePrefix("==> ")
            return listOf(SetupEvent.Stage(title), SetupEvent.Line(line))
        }
        return listOf(SetupEvent.Line(line))
    }

    companion object {
        const val EXIT_MARKER = "GRYONIXNEXUS_EXIT:"
    }
}
