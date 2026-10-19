package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.app.access.AccessCredential
import com.skaymer.gryonixnexus.app.access.AccessCredentialStore
import com.skaymer.gryonixnexus.app.access.InstallReportStore
import com.skaymer.gryonixnexus.app.access.StoredInstallReport
import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.DeploymentStore
import com.skaymer.gryonixnexus.servercontrol.HostKeyPinAccounts
import com.skaymer.gryonixnexus.servercontrol.upsert
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import android.util.Base64 as AndroidBase64

@Serializable
data class DeploymentTransfer(
    val version: Int = CURRENT_VERSION,
    val deployment: Deployment,
    /** The app's ed25519 seed, base64 — Swift's `Data` */
    val sshIdentitySeed: String? = null,
    val sshTransferID: String? = null,
    val dashboardPassword: String? = null,
    val wireGuardSeeds: Map<String, String> = emptyMap(),
    val hostKeyPins: Map<String, String> = emptyMap(),
    val reports: List<TransferReport> = emptyList(),
    val accessCredentials: Map<String, AccessCredential>? = null,
    val installUsers: Map<String, String>? = null,
    /** "vps"/"home" → that machine's own management password */
    val dashboardPasswords: Map<String, String>? = null,
) {
    companion object {
        const val CURRENT_VERSION = 1
    }
}

/** A report inside the bundle */
@Serializable
data class TransferReport(
    val host: String,
    val text: String,
    val savedAt: Double = 0.0,
)

/** The two epochs */
object TransferTime {
    const val APPLE_EPOCH_OFFSET = 978_307_200.0

    fun toApple(epochMillis: Long): Double = epochMillis / 1000.0 - APPLE_EPOCH_OFFSET

    fun fromApple(seconds: Double): Long = ((seconds + APPLE_EPOCH_OFFSET) * 1000).toLong()
}

/** Builds, encodes, decodes and applies a bundle */
class DeploymentTransferService(
    private val secrets: SecretStore,
    private val store: DeploymentStore,
    /** Injected so the JVM tests do not touch android.util.Base64 */
    private val base64: Base64Codec = AndroidBase64Codec,
) {
    interface Base64Codec {
        fun encode(bytes: ByteArray): String
        fun decode(text: String): ByteArray?
    }

    object AndroidBase64Codec : Base64Codec {
        override fun encode(bytes: ByteArray): String =
            AndroidBase64.encodeToString(bytes, AndroidBase64.NO_WRAP)

        override fun decode(text: String): ByteArray? =
            runCatching { AndroidBase64.decode(text, AndroidBase64.NO_WRAP) }.getOrNull()
    }

    var mintKey: suspend (Deployment) -> TransferKey? = { null }

    suspend fun exportFor(deployment: Deployment): DeploymentTransfer =
        export(deployment, mintKey(deployment))

    fun export(deployment: Deployment, transferKey: TransferKey? = null): DeploymentTransfer {
        val id = deployment.id
        val deploymentSecrets = DeploymentSecrets(secrets, id)

        val passwords = LinkedHashMap<String, String>()
        for (node in deployment.nodes) {
            val name = slotName(node) ?: continue
            deploymentSecrets.password(node.sshHost)?.let { passwords[name] = it }
        }

        val pins = LinkedHashMap<String, String>()
        for (node in deployment.nodes) {
            val slot = node.legacySlot
            val pin = if (slot != null) {
                deploymentSecrets.hostKeyPin(slot)
            } else {
                deploymentSecrets.hostKeyPin(node.id)
            } ?: continue
            pins[slot?.name?.lowercase() ?: node.id] = pin
        }

        val overrides = AccessCredentialStore(secrets, id).load()
        return DeploymentTransfer(
            deployment = deployment,
            sshIdentitySeed = (transferKey?.seed ?: deploymentSecrets.identitySeed())?.let(base64::encode),
            sshTransferID = transferKey?.id,
            dashboardPassword = passwords["vps"] ?: passwords["single"],
            hostKeyPins = pins,
            reports = InstallReportStore(secrets, id).load().map {
                TransferReport(it.host, it.text, TransferTime.toApple(it.savedAt))
            },
            accessCredentials = overrides.ifEmpty { null },
            dashboardPasswords = passwords.ifEmpty { null },
        )
    }

    fun encode(transfer: DeploymentTransfer): String = json.encodeToString(transfer)

    fun decode(text: String): DeploymentTransfer {
        val transfer = json.decodeFromString<DeploymentTransfer>(text)
        if (transfer.version > DeploymentTransfer.CURRENT_VERSION) {
            throw UnsupportedVersion(transfer.version)
        }
        return transfer
    }

    class UnsupportedVersion(val version: Int) : Exception("unsupported transfer version $version")

    fun apply(transfer: DeploymentTransfer): Deployment {
        val deployment = transfer.deployment
        val id = deployment.id
        val deploymentSecrets = DeploymentSecrets(secrets, id)

        transfer.sshIdentitySeed?.let { base64.decode(it) }?.let { seed ->
            deploymentSecrets.setIdentitySeed(seed)
            transfer.sshTransferID?.let(deploymentSecrets::setPendingTransfer)
        }

        val perMachine = transfer.dashboardPasswords.orEmpty()
        if (perMachine.isNotEmpty()) {
            for (node in deployment.nodes) {
                val name = slotName(node) ?: continue
                perMachine[name]?.let { deploymentSecrets.setPassword(it, node.sshHost) }
            }
        } else if (transfer.dashboardPassword != null) {
            for (node in deployment.nodes) {
                deploymentSecrets.setPassword(transfer.dashboardPassword, node.sshHost)
            }
        }

        for (node in deployment.nodes) {
            val slot = node.legacySlot
            val pin = transfer.hostKeyPins[slot?.name?.lowercase() ?: node.id] ?: continue
            if (slot != null) deploymentSecrets.setHostKeyPin(pin, slot)
            else secrets.setString(
                HostKeyPinAccounts.current(id, node.id),
                pin,
            )
        }

        val reports = InstallReportStore(secrets, id)
        for (report in transfer.reports) reports.save(report.host, report.text)

        transfer.accessCredentials?.takeIf { it.isNotEmpty() }?.let {
            AccessCredentialStore(secrets, id).save(it)
        }

        store.upsert(deployment)
        return deployment
    }

    private fun slotName(node: DeploymentNode): String? = node.legacySlot?.name?.lowercase()

    companion object {
        const val FILE_EXTENSION = "gryonixserver"

        /** What the file is called */
        fun fileName(deployment: Deployment): String {
            val base = deployment.domain.ifEmpty { deployment.name }.replace("/", "-")
            return "${base.ifEmpty { "server" }}.$FILE_EXTENSION"
        }

        private val json = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
            explicitNulls = false
            prettyPrint = true
        }
    }
}
