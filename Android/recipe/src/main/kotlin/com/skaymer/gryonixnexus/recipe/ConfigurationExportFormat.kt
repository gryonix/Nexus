package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.core.ArtifactKind
import com.skaymer.gryonixnexus.core.DNSRecord

object ConfigurationExportFormat {
    // ─────────────────────────────── DNS ───────────────────────────────

    fun recordsText(records: List<DNSRecord>, domain: String): String =
        records.joinToString("\n") { record ->
            val priority = record.priority?.let { " $it" } ?: ""
            "${record.type.rawValue.uppercase()}\t${nameField(record.name, domain)}\t" +
                "${record.value}$priority"
        }

    fun nameField(name: String, domain: String): String {
        if (name == domain) return "@"
        if (name.endsWith(".$domain")) return name.dropLast(domain.length + 1)
        return name
    }

    // ────────────────────────────── Ports ──────────────────────────────

    /** One `PORT/PROTO purpose` line per requirement — what "Copy" hands over */
    fun portsText(requirements: List<OpenPortRequirement>): String =
        requirements.joinToString("\n") { "${it.port}/${it.proto.label}\t${it.purpose}" }

    /** A human-readable list for a provider's firewall form */
    fun portsTextArtifact(requirements: List<OpenPortRequirement>, summary: String): Artifact {
        val lines = mutableListOf(
            "# Inbound ports to allow on the server (hoster firewall / security group).",
            "# Port/Proto    Purpose",
        )
        requirements.mapTo(lines) { "${it.port}/${it.proto.label}    ${it.purpose}" }
        return Artifact(
            fileName = "gryonixnexus-ports.txt",
            kind = ArtifactKind.FIREWALL_RULES,
            contents = lines.joinToString("\n") + "\n",
            summary = summary,
        )
    }

    fun portsCSVArtifact(requirements: List<OpenPortRequirement>, summary: String): Artifact {
        val lines = mutableListOf("port,protocol,purpose")
        requirements.mapTo(lines) {
            "${it.port},${it.proto.label},${csvField(it.purpose)}"
        }
        return Artifact(
            fileName = "gryonixnexus-ports.csv",
            kind = ArtifactKind.FIREWALL_RULES,
            contents = lines.joinToString("\n") + "\n",
            summary = summary,
        )
    }

    fun csvField(value: String): String {
        if (!value.contains(",") && !value.contains("\"") && !value.contains("\n")) return value
        return "\"" + value.replace("\"", "\"\"") + "\""
    }
}
