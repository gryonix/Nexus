package com.skaymer.gryonixnexus.catalog.storage

import com.skaymer.gryonixnexus.catalog.Apt
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject

/** What a disk says about itself through SMART */
data class DiskHealth(
    val path: String,
    val passed: Boolean?,
    val temperature: Int?,
    val powerOnHours: Int?,
    /** NVMe wear, 0–100 and beyond */
    val wornPercent: Int?,
    /** Reallocated, pending and uncorrectable sectors, or NVMe media errors */
    val badSectors: Int,
    val criticalWarning: Int,
) {
    enum class Verdict { GOOD, WATCH, FAILING, UNKNOWN }

    val verdict: Verdict
        get() = when {
            passed == false || criticalWarning != 0 -> Verdict.FAILING
            passed == null && temperature == null && powerOnHours == null -> Verdict.UNKNOWN
            badSectors > 0 || (wornPercent ?: 0) >= 90 || (temperature ?: 0) >= 65 -> Verdict.WATCH
            else -> Verdict.GOOD
        }

    companion object {
        const val DONE_MARKER = "GRYONIXNEXUS_SMART_DONE"
        private const val HEADER = "### "

        /** Installs smartmontools if needed, then reads every disk */
        fun script(paths: List<String>): String {
            val lines = mutableListOf(
                "#!/bin/bash",
                "set -uo pipefail",
                "if ! command -v smartctl >/dev/null 2>&1; then",
                "  export DEBIAN_FRONTEND=noninteractive",
                "  ${Apt.QUIET} install -y -qq --no-install-recommends smartmontools >/dev/null 2>&1 \\",
                "    || { echo \"smartmontools could not be installed\"; exit 3; }",
                "fi",
            )
            for (path in paths) {
                val quoted = FastStoragePlan.quoted(path)
                lines += "echo \"$HEADER\"$quoted; smartctl --json=c -H -A -i $quoted; echo"
            }
            lines += "echo $DONE_MARKER"
            return lines.joinToString("\n") + "\n"
        }

        fun parse(output: String): List<DiskHealth> {
            val result = mutableListOf<DiskHealth>()
            var path: String? = null
            for (line in output.split("\n")) {
                if (line.startsWith(HEADER)) {
                    path = line.removePrefix(HEADER)
                    continue
                }
                val current = path ?: continue
                if (!line.startsWith("{")) continue
                val json = runCatching { Json.parseToJsonElement(line).jsonObject }.getOrNull() ?: continue
                result += health(current, json)
                path = null
            }
            return result
        }

        private fun health(path: String, json: JsonObject): DiskHealth {
            val nvme = json["nvme_smart_health_information_log"] as? JsonObject
            val table = (json["ata_smart_attributes"] as? JsonObject)?.get("table") as? JsonArray
            fun raw(id: Int): Int = table.orEmpty().mapNotNull { it as? JsonObject }
                .firstOrNull { int(it["id"]) == id }?.let { int((it["raw"] as? JsonObject)?.get("value")) } ?: 0
            return DiskHealth(
                path = path,
                passed = ((json["smart_status"] as? JsonObject)?.get("passed") as? JsonPrimitive)?.booleanOrNull,
                temperature = int((json["temperature"] as? JsonObject)?.get("current")) ?: int(nvme?.get("temperature")),
                powerOnHours = int((json["power_on_time"] as? JsonObject)?.get("hours")) ?: int(nvme?.get("power_on_hours")),
                wornPercent = int(nvme?.get("percentage_used")),
                badSectors = raw(5) + raw(197) + raw(198) + (int(nvme?.get("media_errors")) ?: 0),
                criticalWarning = int(nvme?.get("critical_warning")) ?: 0,
            )
        }

        private fun int(value: JsonElement?): Int? = (value as? JsonPrimitive)?.intOrNull
    }
}
