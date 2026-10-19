package com.skaymer.gryonixnexus.profile

object VPNLink {
    fun firstLink(text: String, scheme: String): String? {
        val prefix = "$scheme://"
        val line = text.lineSequence()
            .map { it.trim() }
            .firstOrNull { it.startsWith(prefix) }
            ?: return null

        if (parses(line)) return line

        val hash = line.indexOf('#')
        if (hash < 0) return null
        val encoded = percentEncodeFragment(line.substring(hash + 1))
        val rebuilt = line.substring(0, hash) + "#" + encoded
        return if (parses(rebuilt)) rebuilt else null
    }

    /** Would this be accepted as an absolute URI? */
    private fun parses(candidate: String): Boolean = try {
        java.net.URI(candidate).isAbsolute
    } catch (_: java.net.URISyntaxException) {
        false
    }

    /** The characters a URI fragment may carry unescaped */
    private const val FRAGMENT_ALLOWED = "!$&'()*+,-./:;=?@_~"

    private fun percentEncodeFragment(fragment: String): String {
        val out = StringBuilder(fragment.length)
        for (byte in fragment.toByteArray(Charsets.UTF_8)) {
            val c = byte.toInt().toChar()
            if (byte >= 0 && (c.isLetterOrDigit() && c.code < 128 || c in FRAGMENT_ALLOWED)) {
                out.append(c)
            } else {
                out.append('%').append("%02X".format(byte.toInt() and 0xFF))
            }
        }
        return out.toString()
    }
}
