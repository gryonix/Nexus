package com.skaymer.gryonixnexus.catalog

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Deployment topology — the two supported scenarios, kept extensible */
@Serializable
enum class Topology(val wireValue: String) {
    @SerialName("singleHost") SINGLE_HOST("singleHost"),                        // scenario A
    @SerialName("vpsRelayWithHomeBackend") VPS_RELAY_WITH_HOME_BACKEND("vpsRelayWithHomeBackend");  // scenario B

    companion object {
        fun from(wireValue: String): Topology? =
            entries.firstOrNull { it.wireValue == wireValue }
    }
}
