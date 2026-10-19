package com.skaymer.gryonixnexus.app.install

import com.skaymer.gryonixnexus.recipe.SetupMarkers
import com.skaymer.gryonixnexus.servercontrol.SetupProgressParser

object InstallFailureText {
    /** Line prefixes that are addressed to the app */
    private val PROTOCOL = listOf(
        SetupMarkers.STEP,
        SetupMarkers.DONE,
        SetupMarkers.DNS_CHECK_FAILED,
        SetupMarkers.PORTS_IN_USE,
        SetupMarkers.REPORT_BEGIN,
        SetupMarkers.REPORT_END,
        SetupProgressParser.EXIT_MARKER,
    )

    fun readable(text: String): String = text
        .lineSequence()
        .filterNot { line -> PROTOCOL.any { marker -> line.trimStart().startsWith(marker) } }
        .joinToString("\n")
        .replace(Regex("\n{3,}"), "\n\n")
        .trim()
}
