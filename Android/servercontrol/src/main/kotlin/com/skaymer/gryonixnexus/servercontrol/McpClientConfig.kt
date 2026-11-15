package com.skaymer.gryonixnexus.servercontrol

/** The MCP client entry for a server and key file */
object McpClientConfig {
    fun text(name: String, user: String, host: String, keyPath: String): String {
        val label = name.lowercase().filter { it.isLetterOrDigit() || it == '-' }.ifEmpty { "server" }
        return """
            {
              "mcpServers": {
                "gryonix-$label": {
                  "command": "ssh",
                  "args": ["-i", "$keyPath", "-o", "BatchMode=yes", "$user@$host"]
                }
              }
            }
        """.trimIndent()
    }
}
