package com.skaymer.gryonixnexus.servercontrol

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ServerAccessOptions(
    /** Whether this device's SSH agent is forwarded into the session */
    @SerialName("agentForwarding") val agentForwarding: Boolean = false,
    /** Where the file browser opens */
    @SerialName("sftpDirectory") val sftpDirectory: String? = null,
    @SerialName("bastion") val bastion: BastionHop? = null,
    @SerialName("fallback") val fallback: FallbackAddress? = null,
    @SerialName("proxyID") val proxyID: String? = null,
) {
    /** Whether anything here is worth storing at all */
    val isEmpty: Boolean get() = this == NONE

    companion object {
        /** Nothing chosen — what every server has until somebody opens Advanced */
        val NONE = ServerAccessOptions()
    }
}

@Serializable
data class BastionHop(
    @SerialName("fleetServerID") val fleetServerID: String? = null,
    /** The typed-in endpoint, when it is not */
    @SerialName("manual") val manual: HostEndpoint? = null,
) {
    /** A hop that names nothing is not a hop */
    val isUsable: Boolean
        get() = !fleetServerID.isNullOrEmpty() || (manual?.isValid == true)
}

@Serializable
data class FallbackAddress(
    /** The address to try */
    @SerialName("host") val host: String = "",
    /** The port to try */
    @SerialName("port") val port: Int? = null,
    /** The jump host this attempt goes through, if any */
    @SerialName("bastion") val bastion: BastionHop? = null,
) {
    val isUsable: Boolean
        get() = host.trim().isNotEmpty() || bastion?.isUsable == true

    fun endpoint(primary: HostEndpoint): HostEndpoint {
        val typed = host.trim()
        return HostEndpoint(
            host = if (typed.isEmpty()) primary.host else typed,
            port = port ?: primary.port,
            user = primary.user,
        )
    }
}

@Serializable
data class ProxyProfile(
    @SerialName("id") val id: String,
    @SerialName("name") val name: String = "",
    @SerialName("kind") val kind: Kind = Kind.SOCKS5,
    @SerialName("host") val host: String = "",
    @SerialName("port") val port: Int = 1080,
    @SerialName("username") val username: String = "",
) {
    @Serializable
    enum class Kind {
        @SerialName("socks5") SOCKS5,
        @SerialName("httpConnect") HTTP_CONNECT,
    }

    /** Enough to dial */
    val isUsable: Boolean get() = host.trim().isNotEmpty() && port in 1..65535

    /** What it is called when nobody named it */
    val displayName: String get() = name.trim().ifEmpty { "$host:$port" }
}
