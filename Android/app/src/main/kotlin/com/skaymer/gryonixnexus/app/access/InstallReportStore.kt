package com.skaymer.gryonixnexus.app.access

import com.skaymer.gryonixnexus.app.secrets.SecretStore
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class StoredInstallReport(
    /** Which machine printed it: "single", "vps" or "home" */
    val host: String,
    val text: String,
    val savedAt: Long = 0L,
)

/** The reports of one deployment, one entry per machine */
class InstallReportStore(
    private val store: SecretStore,
    private val deploymentID: String,
    private val clock: () -> Long = { System.currentTimeMillis() },
) {
    fun load(): List<StoredInstallReport> {
        val text = store.string(account) ?: return emptyList()
        return runCatching { json.decodeFromString<List<StoredInstallReport>>(text) }
            .getOrDefault(emptyList())
    }

    fun save(host: String, text: String) {
        val kept = load().filterNot { it.host == host }
        val reports = kept + StoredInstallReport(host = host, text = text, savedAt = clock())
        store.setString(account, json.encodeToString(reports))
    }

    fun delete() = store.deleteSecret(account)

    private val account: String get() = "install-report-$deploymentID"

    private companion object {
        val json = Json { ignoreUnknownKeys = true }
    }
}
