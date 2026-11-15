package com.skaymer.gryonixnexus.servercontrol

/** How this device reaches a machine behind the VPS */
enum class HomePathChoice(val raw: String) {
    AUTOMATIC("automatic"),
    THROUGH_VPS("throughVPS"),
    LOCAL_NETWORK("localNetwork");

    /** Which links the runner may try, in order */
    data class Plan(val localFirst: Boolean, val usesVPS: Boolean, val localLastResort: Boolean)

    val plan: Plan
        get() = when (this) {
            AUTOMATIC -> Plan(localFirst = true, usesVPS = true, localLastResort = true)
            THROUGH_VPS -> Plan(localFirst = false, usesVPS = true, localLastResort = false)
            LOCAL_NETWORK -> Plan(localFirst = true, usesVPS = false, localLastResort = false)
        }

    companion object {
        fun from(raw: String?): HomePathChoice = entries.firstOrNull { it.raw == raw } ?: AUTOMATIC
    }
}
