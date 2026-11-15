package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.profile.ProxyTunnelText
import com.skaymer.gryonixnexus.profile.advanced.AdvancedBlockList
import com.skaymer.gryonixnexus.profile.advanced.AdvancedGeoIP
import com.skaymer.gryonixnexus.profile.advanced.GeoIPDatParser
import com.skaymer.gryonixnexus.profile.advanced.AdvancedImportReport
import com.skaymer.gryonixnexus.profile.advanced.AdvancedProfile
import com.skaymer.gryonixnexus.profile.advanced.AdvancedSubscription
import com.skaymer.gryonixnexus.profile.advanced.AdvancedTraffic
import com.skaymer.gryonixnexus.profile.advanced.AdvancedXrayConfiguration
import com.skaymer.gryonixnexus.profile.advanced.BlockListParser
import com.skaymer.gryonixnexus.profile.advanced.SubscriptionImport
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

class AdvancedVpnStore(private val secrets: SecretStore, private val filesDir: File) {
    enum class Notice { NEED_HTTPS, SUBSCRIPTION_FAILED, LIST_FAILED, CHOOSE_FIRST, GEOIP_FAILED }

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val _profile = MutableStateFlow(load())
    val profile: StateFlow<AdvancedProfile> = _profile.asStateFlow()
    private val _report = MutableStateFlow<AdvancedImportReport?>(null)
    val report: StateFlow<AdvancedImportReport?> = _report.asStateFlow()
    private val _notice = MutableStateFlow<Notice?>(null)
    val notice: StateFlow<Notice?> = _notice.asStateFlow()
    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()
    private val _traffic = MutableStateFlow<AdvancedTraffic?>(null)
    val traffic: StateFlow<AdvancedTraffic?> = _traffic.asStateFlow()

    private fun load(): AdvancedProfile = runCatching {
        json.decodeFromString<AdvancedProfile>(secrets.string(ACCOUNT) ?: return AdvancedProfile())
    }.getOrDefault(AdvancedProfile())

    fun update(change: (AdvancedProfile) -> AdvancedProfile) {
        val next = change(_profile.value)
        _profile.value = next
        secrets.setString(ACCOUNT, json.encodeToString(AdvancedProfile.serializer(), next))
    }

    // MARK: Import

    fun importText(text: String) {
        val found = SubscriptionImport.parse(text)
        absorb(found)
        _report.value = found
    }

    private fun absorb(found: AdvancedImportReport) = update { profile ->
        val fresh = found.rules.filter { rule ->
            profile.rules.none { it.kind == rule.kind && it.value == rule.value && it.action == rule.action }
        }
        profile.merging(found.servers).copy(rules = profile.rules + fresh)
    }

    suspend fun addSubscription(address: String) {
        val text = address.trim()
        if (!isFetchable(text)) {
            _notice.value = Notice.NEED_HTTPS
            return
        }
        val subscription = AdvancedSubscription(name = URL(text).host, url = text)
        update { it.copy(subscriptions = it.subscriptions + subscription) }
        refresh(subscription.id)
    }

    suspend fun refresh(subscriptionID: String) {
        val subscription = _profile.value.subscriptions.firstOrNull { it.id == subscriptionID } ?: return
        _busy.value = true
        try {
            val found = SubscriptionImport.parse(download(subscription.url))
            apply(found, subscriptionID)
            _report.value = found
            _notice.value = null
        } catch (failure: Exception) {
            _notice.value = Notice.SUBSCRIPTION_FAILED
        } finally {
            _busy.value = false
        }
    }

    private fun apply(found: AdvancedImportReport, subscriptionID: String) = update { profile ->
        val index = profile.subscriptions.indexOfFirst { it.id == subscriptionID }
        if (index < 0) return@update profile
        val old = profile.subscriptions[index].serverIDs.toSet()
        val fresh = found.servers.map { it.id }
        val others = profile.subscriptions.filterIndexed { i, _ -> i != index }.flatMap { it.serverIDs }.toSet()
        val merged = profile.removing(old - fresh.toSet() - others).merging(found.servers)
        val subscriptions = merged.subscriptions.map {
            if (it.id == subscriptionID) it.copy(serverIDs = fresh, updatedAtMillis = System.currentTimeMillis()) else it
        }
        merged.copy(subscriptions = subscriptions)
    }

    suspend fun refreshDue() {
        _profile.value.subscriptions.filter { isDue(it.updatedAtMillis) }.forEach { refresh(it.id) }
        _profile.value.blockLists.filter { isDue(it.updatedAtMillis) }.forEach { refreshBlockList(it.id) }
        val geoip = _profile.value.geoip
        if (AdvancedGeoIP.codes(_profile.value.rules).isNotEmpty() && isDue(geoip.updatedAtMillis, interval = GEOIP_REFRESH_MILLIS)) {
            refreshGeoIP()
        }
    }

    // MARK: GeoIP

    /** Rule country codes missing from the database */
    val missingCountries: Set<String> get() = AdvancedGeoIP.codes(_profile.value.rules) - _profile.value.geoip.ranges.keys

    suspend fun refreshGeoIP() {
        val codes = AdvancedGeoIP.codes(_profile.value.rules)
        val address = _profile.value.geoip.url
        if (codes.isEmpty()) return
        if (!isFetchable(address)) {
            _notice.value = Notice.NEED_HTTPS
            return
        }
        _busy.value = true
        try {
            val data = downloadBytes(address, GEOIP_DOWNLOAD_LIMIT)
            val ranges = withContext(Dispatchers.Default) { GeoIPDatParser.ranges(data, codes) }
            update { it.copy(geoip = it.geoip.copy(ranges = ranges, updatedAtMillis = System.currentTimeMillis())) }
            _notice.value = null
        } catch (failure: Exception) {
            _notice.value = Notice.GEOIP_FAILED
        } finally {
            _busy.value = false
        }
    }

    // MARK: Block lists

    suspend fun addBlockList(address: String) {
        val text = address.trim()
        if (!isFetchable(text)) {
            _notice.value = Notice.NEED_HTTPS
            return
        }
        val list = AdvancedBlockList(url = text)
        update { it.copy(blockLists = it.blockLists + list) }
        refreshBlockList(list.id)
    }

    suspend fun refreshBlockList(id: String) {
        val list = _profile.value.blockLists.firstOrNull { it.id == id } ?: return
        _busy.value = true
        try {
            val domains = BlockListParser.domains(download(list.url))
            update { profile ->
                profile.copy(blockLists = profile.blockLists.map {
                    if (it.id == id) it.copy(domains = domains, updatedAtMillis = System.currentTimeMillis()) else it
                })
            }
            _notice.value = null
        } catch (failure: Exception) {
            _notice.value = Notice.LIST_FAILED
        } finally {
            _busy.value = false
        }
    }

    // MARK: Tunnel

    /** The stored tunnel text, or null when nothing is chosen */
    fun tunnelText(): String? {
        var profile = _profile.value
        if (profile.activeID == null) {
            val first = profile.servers.firstOrNull() ?: return null
            update { it.copy(activeID = first.id) }
            profile = _profile.value
        }
        if (runCatching { AdvancedXrayConfiguration.members(profile) }.getOrNull().isNullOrEmpty()) {
            _notice.value = Notice.CHOOSE_FIRST
            return null
        }
        _notice.value = null
        val text = json.encodeToString(AdvancedProfile.serializer(), profile)
        return ProxyTunnelText.compose("advanced", ImportedTunnels.PROXY_DNS, text)
    }

    val accessLog: File get() = File(filesDir, ACCESS_LOG)

    suspend fun refreshTraffic() {
        val vars = runCatching { download("http://127.0.0.1:${AdvancedTraffic.STATS_PORT}/debug/vars", httpsOnly = false) }
        var traffic = AdvancedTraffic.fromMetrics(vars.getOrDefault(""))
        val log = runCatching { withContext(Dispatchers.IO) { accessLog.takeLast(LOG_TAIL) } }.getOrNull()
        if (log != null) traffic = traffic.copy(requests = AdvancedTraffic.requests(log))
        _traffic.value = traffic
    }

    private fun File.takeLast(bytes: Int): String {
        if (!exists()) return ""
        val data = readBytes()
        return String(data, maxOf(0, data.size - bytes), minOf(bytes, data.size), Charsets.UTF_8)
    }

    // MARK: Download

    private suspend fun download(address: String, httpsOnly: Boolean = true): String =
        String(downloadBytes(address, DOWNLOAD_LIMIT, httpsOnly), Charsets.UTF_8)

    private suspend fun downloadBytes(address: String, limit: Int, httpsOnly: Boolean = true): ByteArray =
        withContext(Dispatchers.IO) {
            require(!httpsOnly || address.startsWith("https://"))
            val connection = URL(address).openConnection() as HttpURLConnection
            connection.connectTimeout = 20_000
            connection.readTimeout = 60_000
            try {
                check(connection.responseCode == 200)
                val bytes = connection.inputStream.use { it.readNBytes(limit + 1) }
                check(bytes.size <= limit)
                bytes
            } finally {
                connection.disconnect()
            }
        }

    companion object {
        private const val ACCOUNT = "vpn.advanced"
        const val ACCESS_LOG = "access.log"
        private const val LOG_TAIL = 65_536
        const val DOWNLOAD_LIMIT = 8 shl 20
        const val REFRESH_MILLIS = 24L * 3600 * 1000
        const val GEOIP_REFRESH_MILLIS = 7 * REFRESH_MILLIS
        const val GEOIP_DOWNLOAD_LIMIT = 64 shl 20

        fun isFetchable(text: String): Boolean = text.startsWith("https://") && runCatching { URL(text).host.isNotEmpty() }.getOrDefault(false)

        fun isDue(updatedAtMillis: Long?, now: Long = System.currentTimeMillis(), interval: Long = REFRESH_MILLIS): Boolean =
            updatedAtMillis == null || now - updatedAtMillis >= interval
    }
}
