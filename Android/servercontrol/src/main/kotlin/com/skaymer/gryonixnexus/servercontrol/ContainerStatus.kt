package com.skaymer.gryonixnexus.servercontrol

data class ContainerStatus(
    val name: String,
    /** Verbatim STATUS column, e.g */
    val status: String,
) {
    val health: HealthLevel
        get() {
            val lowered = status.lowercase()
            if (lowered.contains("not running") || lowered.contains("no such container")) {
                return HealthLevel.WARNING
            }
            if (lowered.contains("unhealthy")) return HealthLevel.CRITICAL
            if (lowered.startsWith("up") || lowered.contains("running")) return HealthLevel.OK
            if (lowered.contains("exit")) return HealthLevel.CRITICAL
            return HealthLevel.WARNING
        }
}
