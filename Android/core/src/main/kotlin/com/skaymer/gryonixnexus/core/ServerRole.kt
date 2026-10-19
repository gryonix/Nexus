package com.skaymer.gryonixnexus.core

/** Server role within the topology */
enum class ServerRole(val wireValue: String) {
    SINGLE_HOST("singleHost"),   // scenario A: single server with a public IP
    VPS_RELAY("vpsRelay"),       // scenario B: VPS — entry point/relay
    HOME_BACKEND("homeBackend"); // scenario B: home server with mail

    companion object {
        fun from(wireValue: String): ServerRole? =
            entries.firstOrNull { it.wireValue == wireValue }
    }
}
