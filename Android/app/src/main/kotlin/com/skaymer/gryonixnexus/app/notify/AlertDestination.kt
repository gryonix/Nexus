package com.skaymer.gryonixnexus.app.notify

import com.skaymer.gryonixnexus.app.shell.ServerSection
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

/** Where a tapped server alert opens */
data class AlertDestination(val deploymentID: String, val section: ServerSection, val service: String? = null) {
    companion object {
        private val APP_KINDS = listOf("gnx.alert.service", "gnx.alert.backup", "gnx.alert.drive_")

        fun from(gnx: JsonObject?, deploymentID: (String) -> String?): AlertDestination? {
            val server = gnx?.get("server_id")?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotEmpty() } ?: return null
            val id = deploymentID(server) ?: return null
            val kind = gnx["kind"]?.jsonPrimitive?.contentOrNull.orEmpty()
            return AlertDestination(id, section(kind), service(kind, gnx["service"]?.jsonPrimitive?.contentOrNull))
        }

        fun kind(gnx: JsonObject?): String = gnx?.get("kind")?.jsonPrimitive?.contentOrNull.orEmpty()

        /** The run a tapped alert reports */
        fun jobID(gnx: JsonObject?): String? =
            gnx?.get("job_id")?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotEmpty() }

        /** Only a service that went down opens its log */
        fun service(kind: String, agentID: String?): String? {
            if (kind != "gnx.alert.service" || agentID.isNullOrEmpty()) return null
            return AgentServiceMapping.serviceIDs(listOf(agentID)).firstOrNull()?.rawValue
        }

        /** Services and backups live in Apps; the rest in General */
        fun section(kind: String): ServerSection =
            if (APP_KINDS.any { kind.startsWith(it) }) ServerSection.APPS else ServerSection.GENERAL
    }
}
