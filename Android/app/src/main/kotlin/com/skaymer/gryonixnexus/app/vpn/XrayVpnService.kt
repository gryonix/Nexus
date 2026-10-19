package com.skaymer.gryonixnexus.app.vpn

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import com.skaymer.gryonixnexus.profile.LocalProxyAccess
import com.skaymer.gryonixnexus.profile.ProxyLinkConfig
import com.skaymer.gryonixnexus.profile.Tun2SocksConfiguration
import com.skaymer.gryonixnexus.profile.XrayConfiguration
import java.io.File
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import xraybridge.Xraybridge

/** Shadowsocks and Xray Reality, on the device */
class XrayVpnService : VpnService() {
    private var tunnel: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                bringDown()
                stopSelf()
                return START_NOT_STICKY
            }
            else -> bringUp()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        bringDown()
        super.onDestroy()
    }

    override fun onRevoke() {
        bringDown()
        stopSelf()
        super.onRevoke()
    }

    private fun bringUp() {
        val stored = pendingLink ?: run {
            failure = "no configuration was handed to the tunnel service"
            _isRunning.value = false
            return
        }
        val (link, dns) = com.skaymer.gryonixnexus.profile.ProxyTunnelText.split(stored)
        try {
            val access = LocalProxyAccess.random()
            val yamlFile = File(filesDir, YAML_NAME)
            yamlFile.writeText(Tun2SocksConfiguration.yaml(access))
            startCore(link, access, com.skaymer.gryonixnexus.profile.ProxyTunnelText.reachableDNS(dns))

            val builder = Builder()
                .setSession("gryonixNexus")
                .addAddress(Tun2SocksConfiguration.ADDRESS, Tun2SocksConfiguration.PREFIX_LENGTH)
                .addRoute("0.0.0.0", 0)
                .apply { com.skaymer.gryonixnexus.profile.ProxyTunnelText.reachableDNS(dns).forEach { addDnsServer(it) } }
                .setMtu(Tun2SocksConfiguration.MTU)
                .setBlocking(false)
            builder.addDisallowedApplication(packageName)
            val descriptor = builder.establish()
                ?: throw IllegalStateException("the system did not give this app an interface")
            tunnel = descriptor
            Tun2Socks.TProxyStartService(yamlFile.absolutePath, descriptor.fd)
            failure = null
            _isRunning.value = true
        } catch (refused: Throwable) {
            bringDown()
            failure = refused.message ?: refused.toString()
            _isRunning.value = false
        }
    }

    /** Shadowsocks runs our own client; everything else runs Xray */
    private fun startCore(link: String, access: LocalProxyAccess, dns: List<String>) {
        val parsed = ProxyLinkConfig.parse(link).let { read ->
            pendingAddress?.let { EndpointPins.pinnedLink(read, it) } ?: read
        }
        val credential = parsed.credential
        if (credential is ProxyLinkConfig.Credential.Shadowsocks) {
            Xraybridge.ssStart(
                "127.0.0.1:${access.port}",
                parsed.endpoint,
                credential.method,
                credential.password,
                access.username,
                access.password,
            )
            return
        }
        val configFile = File(filesDir, "xray-config.json")
        configFile.writeText(XrayConfiguration.json(link = parsed, access = access, dns = dns))
        try {
            Xraybridge.run(filesDir.absolutePath, configFile.absolutePath, 64L shl 20)
        } finally {
            configFile.delete()
        }
    }

    private fun bringDown() {
        runCatching { Tun2Socks.TProxyStopService() }
        runCatching { Xraybridge.ssStop() }
        runCatching { Xraybridge.stop() }
        runCatching { tunnel?.close() }
        File(filesDir, YAML_NAME).delete()
        tunnel = null
        _isRunning.value = false
    }

    companion object {
        private const val YAML_NAME = "tun2socks.yml"
        private const val ACTION_STOP = "com.skaymer.gryonixnexus.STOP_XRAY"

        private val _isRunning = MutableStateFlow(false)
        val isRunning: StateFlow<Boolean> = _isRunning.asStateFlow()

        @Volatile
        var failure: String? = null
            private set

        /** The share link the next start will use */
        @Volatile
        private var pendingLink: String? = null

        /** The pinned address dialed in place of the link's host */
        @Volatile
        private var pendingAddress: String? = null

        fun start(context: Context, link: String, pinnedAddress: String? = null) {
            pendingAddress = pinnedAddress
            pendingLink = link
            context.startService(Intent(context, XrayVpnService::class.java))
        }

        fun stop(context: Context) {
            pendingLink = null
            pendingAddress = null
            context.startService(
                Intent(context, XrayVpnService::class.java).setAction(ACTION_STOP),
            )
        }

        fun counters(): Pair<Long, Long> {
            if (!_isRunning.value) return 0L to 0L
            val stats = runCatching { Tun2Socks.TProxyGetStats() }.getOrNull() ?: return 0L to 0L
            if (stats.size < 4) return 0L to 0L
            return stats[3] to stats[1]
        }
    }
}
