package com.skaymer.gryonixnexus.catalog

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Where a person gets a VPN client configuration from */
@Serializable
enum class VPNClientAccess(val wireValue: String) {
    /** From the app only */
    @SerialName("app") APP("app"),

    /** From the panel's own page only */
    @SerialName("panel") PANEL("panel"),

    @SerialName("both") BOTH("both");

    /** Is the panel's web page published at `vpn.<domain>`? */
    val publishesPanelSite: Boolean get() = this != APP

    /** May the app manage devices for this deployment? */
    val allowsAppManagement: Boolean get() = this != PANEL

    companion object {
        fun from(wireValue: String): VPNClientAccess? =
            entries.firstOrNull { it.wireValue == wireValue }
    }
}
