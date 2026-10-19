package com.skaymer.gryonixnexus.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Distribution profile identifier for serialization/selection in the UI */
@Serializable
enum class DistributionProfileID(val wireValue: String) {
    @SerialName("debian") DEBIAN("debian"),
    @SerialName("ubuntu") UBUNTU("ubuntu");

    companion object {
        fun from(wireValue: String): DistributionProfileID? =
            entries.firstOrNull { it.wireValue == wireValue }
    }
}

/** A server node: addressing + role + distribution profile */
data class ServerNode(
    val role: ServerRole,
    /** nil for the home server */
    val publicAddress: NetworkAddress? = null,
    val vpnAddress: NetworkAddress? = null,
    val distribution: DistributionProfileID = DistributionProfileID.DEBIAN
)
