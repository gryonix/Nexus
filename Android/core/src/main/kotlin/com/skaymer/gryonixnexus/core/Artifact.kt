package com.skaymer.gryonixnexus.core

import java.util.UUID

/** Artifact type — affects application hints and UI highlighting */
enum class ArtifactKind {
    SERVER_CONFIG,   // e.g. main.cf
    DNS_RECORD,      // MX/SPF/DKIM/DMARC
    SHELL_SCRIPT,    // install/apply commands
    KEY_MATERIAL,
    FIREWALL_RULES
}

/** A single generated file + metadata for manual application */
data class Artifact(
    val fileName: String,
    val suggestedPath: String? = null,
    val kind: ArtifactKind,
    val contents: String,
    /** Human-readable purpose */
    val summary: String,
    val server: ServerRole? = null,
    val id: UUID = UUID.randomUUID()
) {
    companion object {
        /** The script that reports and hands the server over */
        const val FINISH_SETUP_NAME = "finish-setup.sh"
    }
}

data class GeneratedBundle(
    val artifacts: List<Artifact>,
    val warnings: List<String> = emptyList(),
    val notes: List<String> = emptyList(),
    /** Per-service scripts, then one that finishes */
    val serviceScripts: List<Artifact> = emptyList(),
)
