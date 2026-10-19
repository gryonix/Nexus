package com.skaymer.gryonixnexus.profile

import java.net.InetAddress
import java.net.ServerSocket
import java.security.SecureRandom

/** One session's loopback SOCKS5 port and login */
data class LocalProxyAccess(val port: Int, val username: String, val password: String) {
    companion object {
        fun random(): LocalProxyAccess =
            LocalProxyAccess(freeLoopbackPort(), token(), token())

        private fun token(): String {
            val bytes = ByteArray(16).also { SecureRandom().nextBytes(it) }
            return bytes.joinToString("") { "%02x".format(it) }
        }

        private fun freeLoopbackPort(): Int =
            ServerSocket(0, 0, InetAddress.getLoopbackAddress()).use { it.localPort }
    }
}
