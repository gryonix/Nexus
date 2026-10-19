package com.skaymer.gryonixnexus.profile

/** Where an `.ovpn` says to connect, and nothing else */
object OpenVPNRemote {
    sealed interface ParseFailure {
        data object NoDirectives : ParseFailure

        /** A profile that names no server (`remote`) to connect to */
        data object NoRemote : ParseFailure
    }

    class ParseException(val failure: ParseFailure) : Exception(failure.toString())

    @Throws(ParseException::class)
    fun endpoint(text: String): String {
        val lines = text.replace("\r\n", "\n").replace('\r', '\n')
            .split('\n')
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") && !it.startsWith(";") }
        if (lines.isEmpty()) throw ParseException(ParseFailure.NoDirectives)

        val remote = lines.firstOrNull { it == "remote" || it.startsWith("remote ") || it.startsWith("remote\t") }
            ?: throw ParseException(ParseFailure.NoRemote)
        val fields = remote.split(' ', '\t').filter { it.isNotEmpty() }
        val host = fields.getOrNull(1) ?: throw ParseException(ParseFailure.NoRemote)
        val port = fields.getOrNull(2)?.toIntOrNull()
        return if (port != null && port in 1..65_535) "$host:$port" else host
    }
}
