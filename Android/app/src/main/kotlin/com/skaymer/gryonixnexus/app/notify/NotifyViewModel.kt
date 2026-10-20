package com.skaymer.gryonixnexus.app.notify

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import gryonixnexusd.v1.NotifyChannel
import gryonixnexusd.v1.NotifyChecks
import gryonixnexusd.v1.NotifySettings
import gryonixnexusd.v1.SetNotifySettingsRequest
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the notifications screen shows for one server */
data class NotifyScreenState(
    val settings: NotifySettings? = null,
    val isWorking: Boolean = false,
    val message: String? = null,
    val isError: Boolean = false,
    /** Whether the last test went out */
    val testSent: Boolean = false,
    /** This phone now gets the server's alerts */
    val deviceRegistered: Boolean = false,
)

class NotifyViewModel(
    private val scope: CoroutineScope,
    private val client: suspend (Deployment) -> AgentClient,
    private val release: suspend (Deployment) -> Unit = {},
    /** Where the app-wide wishes and their sync marks live */
    private val store: SettingsStore? = null,
    /** Gets this phone's push token for a relay */
    private val pushToken: suspend (relayUrl: String) -> String = { error("push is not set up") },
    /** This phone's version and language, as the relay stores them */
    private val appVersion: String = "",
    private val locale: String = "",
    /** The token Firebase last gave this phone, if any */
    private val cachedToken: () -> String? = { null },
    /** This app's SSH public key for a server */
    private val appKey: (Deployment) -> String = { "" },
    private val deviceProof: () -> String = { "" },
    /** What the server's list of devices calls this phone */
    private val deviceName: String = "",
    /** The agent on one particular machine of a server */
    private val hostClient: suspend (Deployment, SSHHostID) -> AgentClient = { deployment, _ -> client(deployment) },
) {
    private val _state = MutableStateFlow(NotifyScreenState())
    val state: StateFlow<NotifyScreenState> = _state.asStateFlow()

    fun load(deployment: Deployment) = call(deployment) { copy(settings = it.getNotifySettings()) }

    /** The app-wide wishes, the default for every server */
    val preferences: NotifyPreferences
        get() = store?.let { NotifyPreferences.load(it) } ?: NotifyPreferences()

    /** The app-wide channel, the default for every server */
    val channelDefault: NotifyChannelDefault
        get() = store?.let { NotifyChannelDefault.load(it) } ?: NotifyChannelDefault()

    /** Whether a server follows the app-wide channel */
    fun followsApp(deployment: Deployment, settings: NotifySettings): Boolean {
        val store = store ?: return false
        return !NotifyChannelDefault.keepsOwn(settings, deployment.id.toString(), channelDefault, store)
    }

    fun save(deployment: Deployment, request: SetNotifySettingsRequest, followsApp: Boolean? = null) = call(deployment) {
        followsApp?.let { store?.setBoolean(NotifyChannelDefault.ownKey(deployment.id.toString()), !it) }
        val chosen = if (followsApp == true) channelDefault.applied(request) else request
        val checks = if (chosen.custom_checks) chosen.checks else preferences.checks
        val key = runCatching { appKey(deployment) }.getOrDefault("")
        val saved = it.setNotifySettings(chosen.copy(checks = checks, app_public_key = key))
        mirror(deployment, saved)
        store?.remove(NotifyPreferences.syncedKey(deployment.id.toString()))
        copy(settings = saved, message = saved.last_error.ifEmpty { null }, isError = saved.last_error.isNotEmpty())
    }

    /** Registers this phone with the server's relay */
    fun registerThisDevice(deployment: Deployment) = call(deployment) {
        val token = pushToken(settings?.relay_url.orEmpty())
        val saved = it.registerNotifyDevice("fcm", token, appVersion, locale, preferences.muted, deviceProof(), deviceName)
        mirror(deployment, saved, token)
        copy(settings = saved, deviceRegistered = true)
    }

    /** The token this phone registers with */
    fun thisToken(): String? = cachedToken()

    /** Stops one device getting this server's pushes */
    fun remove(deployment: Deployment, token: String) = call(deployment) {
        copy(settings = it.unregisterNotifyDevice(token))
    }

    fun test(deployment: Deployment) = call(deployment) {
        val result = it.sendTestNotification()
        copy(settings = it.getNotifySettings(), testSent = result.ok, message = result.message.ifEmpty { null },
            isError = !result.ok)
    }

    /** Gives this server the app-wide wishes once they change */
    fun sync(deployment: Deployment) {
        val store = store ?: return
        if (!canManage(deployment)) return
        val wanted = preferences
        val channel = channelDefault
        val key = NotifyPreferences.syncedKey(deployment.id.toString())
        val own = store.boolean(NotifyChannelDefault.ownKey(deployment.id.toString()))
        val mark = wanted.fingerprint + locale + "k" + "h${deployment.agentHosts.size}" +
            tokenMark(cachedToken()) + "p2" + channel.fingerprint + (own?.let { if (it) 1 else 0 } ?: 2)
        if (store.string(key) == mark) return
        scope.launch {
            try {
                val agent = client(deployment)
                val current = agent.getNotifySettings()
                RelayServers.remember(store, current.server_id, deployment.id, deployment.servicesHost)
                val publicKey = runCatching { appKey(deployment) }.getOrDefault("")
                val follows = !NotifyChannelDefault.keepsOwn(current, deployment.id.toString(), channel, store)
                val request = syncRequest(current, wanted, locale.ifEmpty { current.language }, publicKey,
                    channel.takeIf { follows })
                request?.let { agent.setNotifySettings(it) }
                val sends = request ?: draft(current, current.language)
                val token = if (sends.channel == NotifyChannel.NOTIFY_CHANNEL_RELAY) tokenFor(sends.relay_url) else null
                if (token != null) {
                    agent.registerNotifyDevice("fcm", token, appVersion, locale, wanted.muted, deviceProof(), deviceName)
                }
                if (!mirror(deployment, agent.getNotifySettings())) return@launch
                store.setString(key, mark)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
            }
        }
    }

    /** Every agent server learns the app-wide choice */
    fun syncAll(deployments: List<Deployment>) {
        deployments.filter { it.usesAgent }.forEach { sync(it) }
    }

    /** This phone's token, fetched when Firebase has none yet */
    private suspend fun tokenFor(relayUrl: String): String? =
        cachedToken() ?: try {
            pushToken(relayUrl)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            null
        }

    /** Every other machine sends its alerts the same way */
    private suspend fun mirror(deployment: Deployment, primary: NotifySettings, token: String? = cachedToken()): Boolean {
        val key = runCatching { appKey(deployment) }.getOrDefault("")
        var allDone = true
        for (host in deployment.agentHosts.filter { it != deployment.servicesHost }) {
            try {
                val agent = hostClient(deployment, host)
                val current = agent.getNotifySettings()
                store?.let { RelayServers.remember(it, current.server_id, deployment.id, host) }
                mirrorRequest(primary, current, key)?.let { agent.setNotifySettings(it) }
                if (primary.channel == NotifyChannel.NOTIFY_CHANNEL_RELAY && token != null) {
                    agent.registerNotifyDevice("fcm", token, appVersion, locale, preferences.muted, deviceProof(), deviceName)
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                allDone = false
            }
        }
        return allDone
    }

    private fun call(deployment: Deployment, body: suspend NotifyScreenState.(AgentClient) -> NotifyScreenState) {
        _state.value = _state.value.copy(
            isWorking = true, message = null, isError = false, testSent = false, deviceRegistered = false,
        )
        scope.launch {
            _state.value = try {
                _state.value.body(client(deployment)).copy(isWorking = false)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                _state.value.copy(isWorking = false, message = failure.message ?: failure.toString(), isError = true)
            }
        }
    }

    companion object {
        const val DEFAULT_RELAY_URL = "https://push.gryonix.com"

        fun canManage(deployment: Deployment): Boolean = deployment.usesAgent

        /** The editable copy of what the agent holds */
        fun draft(settings: NotifySettings?, language: String): SetNotifySettingsRequest = SetNotifySettingsRequest(
            channel = settings?.channel?.takeIf { it != NotifyChannel.NOTIFY_CHANNEL_UNSPECIFIED }
                ?: NotifyChannel.NOTIFY_CHANNEL_OFF,
            relay_url = settings?.relay_url?.ifEmpty { null } ?: DEFAULT_RELAY_URL,
            ntfy_url = settings?.ntfy_url?.ifEmpty { null } ?: "https://ntfy.sh",
            ntfy_topic = settings?.ntfy_topic?.ifEmpty { null } ?: randomTopic(),
            checks = settings?.checks ?: NotifyChecks(raid = true, smart = true, disk_space = true, disk_space_percent = 90),
            language = language,
            custom_checks = settings?.custom_checks ?: false,
        )

        /** The request a server needs to match, if any */
        fun syncRequest(
            current: NotifySettings,
            wanted: NotifyPreferences,
            language: String,
            appKey: String,
            channel: NotifyChannelDefault? = null,
        ): SetNotifySettingsRequest? {
            val checks = if (current.custom_checks) current.checks else wanted.checks
            val keyKnown = appKey.isEmpty() || current.quiet_keys.any { appKey.startsWith(it) }
            val inStep = channel?.matches(current) ?: true
            if (current.checks == checks && current.language == language && keyKnown && inStep) return null
            val request = draft(current, language).copy(checks = checks, app_public_key = appKey)
            return channel?.applied(request) ?: request
        }

        /** What another machine needs to match the main one */
        fun mirrorRequest(primary: NotifySettings, current: NotifySettings, appKey: String): SetNotifySettingsRequest? {
            val wanted = draft(primary, primary.language).copy(ntfy_topic = primary.ntfy_topic)
            val have = draft(current, current.language).copy(ntfy_topic = current.ntfy_topic)
            val keyKnown = appKey.isEmpty() || current.quiet_keys.any { appKey.startsWith(it) }
            if (wanted == have && keyKnown) return null
            return wanted.copy(app_public_key = appKey)
        }

        fun randomTopic(): String = "gnx-" + UUID.randomUUID().toString().replace("-", "").take(20)

        fun canSave(request: SetNotifySettingsRequest): Boolean = when (request.channel) {
            NotifyChannel.NOTIFY_CHANNEL_RELAY -> request.relay_url.startsWith("https://") || request.relay_url.startsWith("http://")
            NotifyChannel.NOTIFY_CHANNEL_NTFY -> request.ntfy_topic.isNotBlank() && request.ntfy_url.isNotBlank()
            NotifyChannel.NOTIFY_CHANNEL_OFF -> true
            else -> false
        }
    }

    /** A new push token makes the server learn it again */
    private fun tokenMark(token: String?): String {
        if (token.isNullOrEmpty()) return ""
        val digest = java.security.MessageDigest.getInstance("SHA-256").digest(token.toByteArray())
        return "t" + digest.take(8).joinToString("") { "%02x".format(it) }
    }
}
