package com.skaymer.gryonixnexus.core

interface SecurityPolicy {
    val minimumTLSVersion: TLSVersion
    /** e.g */
    val dkimKeyBits: Int
    /** always false by default */
    val allowOpenRelay: Boolean
    val ssh: SSHHardening
}

enum class TLSVersion { V1_2, V1_3 }

data class SSHHardening(
    val permitRootLogin: Boolean = false,
    /** false — keys only */
    val passwordAuthentication: Boolean = false,
    val port: Int = 22
)

/** Concrete secure default values */
class DefaultSecurityPolicy : SecurityPolicy {
    override val minimumTLSVersion = TLSVersion.V1_2
    override val dkimKeyBits = 2048
    override val allowOpenRelay = false
    override val ssh = SSHHardening()
}

/** The scenario-B tunnel's own interface and port */
object WireGuardDefaults {
    const val INTERFACE_NAME = "wg0"
    const val LISTEN_PORT = 51820
}
