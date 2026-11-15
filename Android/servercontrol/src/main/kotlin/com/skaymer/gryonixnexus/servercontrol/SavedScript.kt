package com.skaymer.gryonixnexus.servercontrol

import kotlinx.serialization.Serializable

/** A saved shell snippet */
@Serializable
data class SavedScript(
    val id: String,
    val name: String,
    val body: String,
    /** Servers it is offered for; empty means every server */
    val deploymentIDs: List<String> = emptyList(),
) {
    val isValid: Boolean get() = name.isNotBlank() && body.isNotBlank()

    fun appliesTo(deploymentID: String): Boolean = deploymentIDs.isEmpty() || deploymentID in deploymentIDs

    /** Text typed into a terminal, ending in a newline */
    val terminalInput: String get() = body.trim('\n', '\r') + "\n"

    /** The command run through the SSH exec path */
    val execCommand: String get() = "sh -c " + ShellQuoting.singleQuoted(body)
}

/** Edits on the saved scripts */
object SavedScriptList {
    fun available(deploymentID: String, all: List<SavedScript>): List<SavedScript> =
        all.filter { it.appliesTo(deploymentID) }

    fun upserting(script: SavedScript, all: List<SavedScript>): List<SavedScript> =
        if (all.any { it.id == script.id }) all.map { if (it.id == script.id) script else it } else all + script

    fun removing(id: String, all: List<SavedScript>): List<SavedScript> = all.filter { it.id != id }

    /** Forgets a deleted server in every script */
    fun forgettingServer(id: String, all: List<SavedScript>): List<SavedScript> =
        all.map { it.copy(deploymentIDs = it.deploymentIDs - id) }
}
