package com.skaymer.gryonixnexus.servercontrol

data class Mailbox(
    /** The address exactly as the server listed it */
    val address: String,
    val detail: String? = null,
) {
    val id: String get() = address

    val localPart: String get() = address.substringBefore('@', "")

    val domain: String
        get() = address.split("@").let { if (it.size == 2) it[1] else "" }

    /** Whether the app may act on this mailbox at all */
    val isManageable: Boolean
        get() = CommandCatalog.DockerMailserver.isValidAddress(address)
}

object MailboxListParser {
    fun parse(output: String): List<Mailbox> {
        val mailboxes = mutableListOf<Mailbox>()
        val seen = mutableSetOf<String>()
        for (rawLine in ANSIStripper.strip(output).split("\n")) {
            val line = rawLine.trim().trim('*').trim()
            val separator = line.indexOfFirst { it == ' ' || it == '\t' }
            if (separator < 0) {
                if (!isAddress(line) || !seen.add(line)) continue
                mailboxes += Mailbox(line, null)
                continue
            }
            val address = line.substring(0, separator)
            if (!isAddress(address) || !seen.add(address)) continue
            val detail = line.substring(separator).trim()
            mailboxes += Mailbox(address, detail.ifEmpty { null })
        }
        return mailboxes
    }

    private fun isAddress(token: String): Boolean {
        if (token.isEmpty()) return false
        if (token.any { it in "()<>[]{},;:\"'\\|" }) return false
        val parts = token.split("@")
        if (parts.size != 2 || parts[0].isEmpty() || parts[1].isEmpty()) return false
        return parts[1].contains(".") && token.none { it.isWhitespace() }
    }
}
