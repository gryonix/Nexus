package com.skaymer.gryonixnexus.app.tv

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import com.skaymer.gryonixnexus.app.licensing.LicensePlan
import com.skaymer.gryonixnexus.app.licensing.LicenseStatus
import com.skaymer.gryonixnexus.app.licensing.LicenseStore
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.servers.DeploymentTransferService
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.tvlink.TvAddress
import com.skaymer.gryonixnexus.tvlink.TvLicenceVouch
import com.skaymer.gryonixnexus.tvlink.TvLinkClient
import com.skaymer.gryonixnexus.tvlink.TvLinkException
import com.skaymer.gryonixnexus.tvlink.TvLinkService
import com.skaymer.gryonixnexus.tvlink.TvMessage
import com.skaymer.gryonixnexus.tvlink.TvPairedTv
import com.skaymer.gryonixnexus.tvlink.TvPairedTvStore
import com.skaymer.gryonixnexus.tvlink.TvPairingAttempt
import com.skaymer.gryonixnexus.tvlink.TvPairingCode
import com.skaymer.gryonixnexus.tvlink.TvPeer
import com.skaymer.gryonixnexus.tvlink.TvRefusal
import com.skaymer.gryonixnexus.tvlink.TvSecretStoring
import com.skaymer.gryonixnexus.tvlink.TvSentServer
import java.io.File
import java.util.Base64
import java.util.concurrent.ConcurrentLinkedQueue
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** An Apple TV seen on the network. */
data class TvNearby(val name: String, val tvId: String?, val address: TvAddress, val awakeAt: Long? = null) {
    /** A sleeping TV's record keeps an old time. */
    fun isAwake(now: Long): Boolean =
        awakeAt != null && kotlin.math.abs(now - awakeAt) <= TvLinkService.AWAKE_FRESHNESS_SECONDS
}

/** The TV refused a request. */
class TvRequestRefused(val code: String) : Exception("refused: $code")

/** Pairing keys in the app's encrypted store. */
class SecretStoreTvSecrets(private val secrets: SecretStore) : TvSecretStoring {
    override fun store(secret: String, account: String) = secrets.setString(account, secret)
    override fun secret(account: String): String? = secrets.string(account)
    override fun delete(account: String) = secrets.deleteSecret(account)
}

fun awakeTvs(tvs: List<TvPairedTv>, nearby: List<TvNearby>, now: Long): List<TvPairedTv> =
    seenTvs(tvs, nearby.filter { it.isAwake(now) })

fun seenTvs(tvs: List<TvPairedTv>, nearby: List<TvNearby>): List<TvPairedTv> {
    val seen = nearby.mapNotNull { it.tvId }.toSet()
    return tvs.filter { it.id in seen }
}

class AppleTvLink(
    context: Context,
    file: File,
    secrets: SecretStore,
    private val license: LicenseStore,
    private val transfer: DeploymentTransferService,
) {
    private val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val store = TvPairedTvStore(file, SecretStoreTvSecrets(secrets))

    private val _tvs = MutableStateFlow(store.all().sortedBy { it.name })
    val tvs: StateFlow<List<TvPairedTv>> = _tvs.asStateFlow()
    private val _nearby = MutableStateFlow<List<TvNearby>>(emptyList())
    val nearby: StateFlow<List<TvNearby>> = _nearby.asStateFlow()

    private val phone: TvPeer get() = TvPeer(license.thisDevice(), Build.MODEL.orEmpty().ifBlank { "Android" })

    private var discovery: NsdManager.DiscoveryListener? = null
    private var watchers = 0
    private val pending = ConcurrentLinkedQueue<NsdServiceInfo>()
    @Volatile private var resolving = false

    @Synchronized
    fun startBrowsing() {
        watchers += 1
        if (discovery != null) return
        _nearby.value = emptyList()
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onServiceFound(info: NsdServiceInfo) {
                pending.add(info)
                resolveNext()
            }
            override fun onServiceLost(info: NsdServiceInfo) {
                _nearby.value = _nearby.value.filterNot { it.name == info.serviceName }
            }
        }
        discovery = listener
        runCatching { nsd.discoverServices(TvLinkService.NSD_TYPE, NsdManager.PROTOCOL_DNS_SD, listener) }
    }

    @Synchronized
    fun stopBrowsing() {
        watchers = maxOf(0, watchers - 1)
        if (watchers > 0) return
        discovery?.let { runCatching { nsd.stopServiceDiscovery(it) } }
        discovery = null
        pending.clear()
        _nearby.value = emptyList()
    }

    /** One resolve at a time: older NSD refuses a second. */
    @Suppress("DEPRECATION")
    private fun resolveNext() {
        synchronized(this) {
            if (resolving) return
            resolving = true
        }
        val info = pending.poll() ?: run { resolving = false; return }
        nsd.resolveService(info, object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) = done()
            override fun onServiceResolved(resolved: NsdServiceInfo) {
                val host = resolved.host?.hostAddress
                if (host != null) {
                    val id = resolved.attributes[TvLinkService.ID_KEY]?.decodeToString()
                    val awakeAt = resolved.attributes[TvLinkService.AWAKE_KEY]?.decodeToString()?.toLongOrNull()
                    val address = TvAddress(host.substringBefore('%'), resolved.port)
                    val found = TvNearby(resolved.serviceName, id, address, awakeAt)
                    _nearby.value = (_nearby.value.filterNot { it.name == found.name } + found).sortedBy { it.name }
                }
                done()
            }
            private fun done() {
                resolving = false
                resolveNext()
            }
        })
    }

    /** TVs on the network not paired yet. */
    fun unpaired(nearby: List<TvNearby>, tvs: List<TvPairedTv>): List<TvNearby> {
        val known = tvs.map { it.id }.toSet()
        return nearby.filter { it.tvId == null || it.tvId !in known }
    }

    suspend fun beginPairing(address: TvAddress): TvPairingAttempt = TvPairingAttempt.start(address, phone)

    suspend fun finishPairing(attempt: TvPairingAttempt, code: TvPairingCode) {
        val result = attempt.enter(code)
        val tv = TvPairedTv(result.peer.id, result.peer.name, attempt.address, System.currentTimeMillis() / 1000)
        store.save(tv, result.pairingKey)
        reload()
        runCatching { exchange(TvMessage(t = TvMessage.LICENCE), tv, lastAddress = false) }
    }

    /** Quietly vouches to TVs whose app is on screen. */
    suspend fun vouchAll() = vouch { awakeTvs(store.all(), _nearby.value, System.currentTimeMillis() / 1000) }

    /** Vouches to every paired TV the network finds. */
    suspend fun confirmNow() = vouch { seenTvs(store.all(), _nearby.value) }

    private suspend fun vouch(targets: () -> List<TvPairedTv>) {
        if (store.all().isEmpty()) return
        startBrowsing()
        try {
            delay(2_000)
            targets().forEach { tv ->
                runCatching { exchange(TvMessage(t = TvMessage.LICENCE), tv, lastAddress = false) }
            }
        } finally {
            stopBrowsing()
        }
    }

    /** Sends servers with their keys over the encrypted link. */
    suspend fun send(deployments: List<Deployment>, tv: TvPairedTv) {
        val items = deployments.map { deployment ->
            val text = transfer.encode(transfer.export(deployment))
            TvSentServer(deployment.id, deployment.name, Base64.getEncoder().encodeToString(text.toByteArray()))
        }
        exchange(TvMessage(t = TvMessage.PUT, items = items), tv)
    }

    /** Unpairs on the TV when it answers, and here regardless. */
    suspend fun forget(tv: TvPairedTv) {
        runCatching { exchange(TvMessage(t = TvMessage.UNPAIR), tv) }
        store.remove(tv.id)
        reload()
    }

    private suspend fun exchange(request: TvMessage, tv: TvPairedTv, lastAddress: Boolean = true): TvMessage {
        val key = store.pairingKey(tv.id) ?: throw TvLinkException.Refused(TvRefusal.UNKNOWN_PHONE)
        val withLicence = request.copy(licence = vouch())
        var last: Exception = TvLinkException.Closed()
        for (address in addresses(tv, lastAddress)) {
            try {
                val answer = TvLinkClient.exchange(listOf(withLicence), address, phone, tv.id, key).single()
                if (answer.t == TvMessage.ERROR) throw TvRequestRefused(answer.code.orEmpty())
                record(answer, tv, address)
                return answer
            } catch (error: TvLinkException.Refused) {
                throw error
            } catch (error: TvRequestRefused) {
                throw error
            } catch (error: Exception) {
                last = error
            }
        }
        throw last
    }

    /** NSD first, then where it answered last if allowed. */
    private fun addresses(tv: TvPairedTv, lastAddress: Boolean): List<TvAddress> {
        val found = _nearby.value.filter { it.tvId == tv.id }.map { it.address }
        return if (lastAddress) (found + listOfNotNull(tv.address)).distinct() else found
    }

    private fun record(answer: TvMessage, tv: TvPairedTv, address: TvAddress) {
        val current = store.record(tv.id) ?: return
        val sent = if (answer.t == TvMessage.SERVERS) answer.items.orEmpty() else current.sent
        store.save(current.copy(sent = sent, address = address, vouchedAt = System.currentTimeMillis() / 1000))
        reload()
    }

    private fun reload() {
        _tvs.value = store.all().sortedBy { it.name }
    }

    private fun vouch(): TvLicenceVouch = when (val status = license.status.value) {
        is LicenseStatus.Active -> {
            val token = license.storedTokenText()
            TvLicenceVouch(
                active = true,
                plan = status.plan.name.lowercase(),
                expires = status.expires,
                token = token,
                device = if (token != null) license.thisDevice() else null,
            )
        }
        else -> TvLicenceVouch(active = false)
    }
}
