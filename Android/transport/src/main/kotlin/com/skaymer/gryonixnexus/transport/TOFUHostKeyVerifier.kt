package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import java.security.PublicKey
import java.util.Base64
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import net.schmizz.sshj.common.Buffer
import net.schmizz.sshj.common.KeyType
import net.schmizz.sshj.transport.verification.HostKeyVerifier

class TOFUHostKeyVerifier(
    private val hostLabel: String,
    private val pinnedKey: String?,
    /** Somewhere other than the handshake thread */
    private val reporter: Executor = SHARED_REPORTER,
    private val onPin: (String) -> Unit,
) : HostKeyVerifier {
    override fun verify(hostname: String, port: Int, key: PublicKey): Boolean {
        val presented = openSSHString(key)
        val pinned = pinnedKey
        if (pinned == null) {
            reporter.execute { onPin(presented) }
            return true
        }
        if (presented == pinned) return true
        throw ServerControlError.HostKeyMismatch(hostLabel)
    }

    override fun findExistingAlgorithms(hostname: String, port: Int): List<String> = emptyList()

    companion object {
        private val SHARED_REPORTER: Executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "gryonixnexus-hostkey-pin").apply { isDaemon = true }
        }

        /** The key as `authorized_keys`/`known_hosts` spell it: "algo base64" */
        internal fun openSSHString(key: PublicKey): String {
            val type = KeyType.fromKey(key)
            val blob = Buffer.PlainBuffer().putPublicKey(key).compactData
            return "${type.toString()} ${Base64.getEncoder().encodeToString(blob)}"
        }
    }
}
