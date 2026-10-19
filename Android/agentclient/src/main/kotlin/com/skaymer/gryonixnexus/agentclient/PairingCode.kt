package com.skaymer.gryonixnexus.agentclient

/** Parsing for the code `gryonixnexusd pair-code` prints */
object PairingCode {
    fun parse(output: String): String? {
        val line = output.lineSequence()
            .map { it.trim() }
            .lastOrNull { it.isNotEmpty() }
            ?: return null
        val token = line.split(Regex("\\s+")).lastOrNull().orEmpty()
        return token.ifEmpty { null }
    }
}
