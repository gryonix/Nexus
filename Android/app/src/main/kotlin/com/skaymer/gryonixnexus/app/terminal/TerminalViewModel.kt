package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.transport.TerminalEndpoint
import com.skaymer.gryonixnexus.transport.TerminalEvent
import com.skaymer.gryonixnexus.transport.TerminalLogin
import com.skaymer.gryonixnexus.transport.TerminalRoutesFailed
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the terminal screen is showing */
data class TerminalState(
    val isConnecting: Boolean = false,
    val isOpen: Boolean = false,
    /** Why it ended, when it ended badly */
    val errorMessage: String? = null,
    val revision: Long = 0,
    /** The route the shell is open on */
    val route: TerminalEndpoint.Kind? = null,
    /** Which automatic reconnect is under way, 0 for none */
    val reconnectAttempt: Int = 0,
    /** No route answered, so a tunnel may help */
    val noRouteAnswered: Boolean = false,
)

class TerminalViewModel(
    private val scope: CoroutineScope,
    private val sessions: (List<TerminalEndpoint>, TerminalLogin) -> TerminalTransport,
    /** The words of a notice line */
    private val notices: (Notice) -> String = { it.name },
    /** Remembers the route that answered */
    private val onConnected: (TerminalEndpoint) -> Unit = {},
    private val pauses: List<Long> = RECONNECT_PAUSES_MS,
    /** Typed into the shell each time it opens */
    private val startupInput: ByteArray? = null,
    /** Input waiting for this shell, taken once it opens */
    private val queuedInput: () -> ByteArray? = { null },
) {
    enum class Notice { LOST, RECONNECTED }

    private data class Request(
        val routes: List<TerminalEndpoint>,
        val login: TerminalLogin,
        val columns: Int,
        val rows: Int,
    )

    private val _state = MutableStateFlow(TerminalState())
    val state: StateFlow<TerminalState> = _state.asStateFlow()

    val emulator = TerminalEmulator()

    private var transport: TerminalTransport? = null
    private var request: Request? = null
    private var pump: Job? = null
    private var reader: Job? = null
    private var redial: Job? = null

    /** Open a shell by the first route that answers */
    fun open(
        routes: List<TerminalEndpoint>,
        login: TerminalLogin,
        columns: Int,
        rows: Int,
    ) {
        if (transport != null || _state.value.isConnecting || redial?.isActive == true) return
        emulator.reset()
        emulator.resize(columns, rows)
        request = Request(routes, login, columns, rows)
        dialAgain()
    }

    /** The same routes again, after a failure */
    fun retry() {
        if (request == null || transport != null || _state.value.isConnecting) return
        redial?.cancel()
        dialAgain()
    }

    private fun dialAgain() {
        _state.value = TerminalState(isConnecting = true, revision = _state.value.revision + 1)
        pump = scope.launch {
            val failure = connect() ?: return@launch
            val unanswered = failure is TerminalRoutesFailed || failure is ServerControlError.ConnectionFailed
            finish(described(failure), unanswered)
        }
    }

    /** Every tried way, in the app's words */
    private fun described(failure: Exception): String = TerminalRoutes.describe(
        failure,
        request?.routes.orEmpty(),
        title = { kind -> com.skaymer.gryonixnexus.app.notify.OperationNotices.text(TerminalRoutes.titleRes(kind)) },
        hint = com.skaymer.gryonixnexus.app.notify.OperationNotices.text(com.skaymer.gryonixnexus.R.string.terminal_direct_only_hint),
    )

    /** Null once the shell is live */
    private suspend fun connect(): Exception? {
        val wanted = request ?: return null
        val live = sessions(wanted.routes, wanted.login)
        transport = live
        reader?.cancel()
        reader = scope.launch { live.output.collect { handle(it, live) } }
        return try {
            live.start(wanted.columns, wanted.rows)
            live.connectedRoute?.let(onConnected)
            startupInput?.let { live.send(it) }
            queuedInput()?.let { live.send(it) }
            _state.value = TerminalState(
                isOpen = true,
                route = live.connectedRoute?.kind,
                revision = _state.value.revision + 1,
            )
            null
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            reader?.cancel()
            if (transport === live) transport = null
            failure
        }
    }

    private fun handle(event: TerminalEvent, source: TerminalTransport) {
        if (source !== transport) return
        when (event) {
            is TerminalEvent.Output -> {
                emulator.feed(event.bytes)
                bump()
            }
            is TerminalEvent.Closed -> {
                transport = null
                val reason = event.reason
                if (reason != null && request != null) reconnect(reason) else finish(reason)
            }
        }
    }

    /** A dropped link comes back without a tap */
    private fun reconnect(reason: String) {
        redial?.cancel()
        notice(Notice.LOST)
        redial = scope.launch {
            for ((index, pause) in pauses.withIndex()) {
                _state.value = TerminalState(reconnectAttempt = index + 1, revision = _state.value.revision + 1)
                delay(pause)
                if (connect() == null) {
                    notice(Notice.RECONNECTED)
                    return@launch
                }
            }
            finish(reason)
        }
    }

    fun send(data: ByteArray) {
        val live = transport ?: return
        scope.launch { live.send(data) }
    }

    fun resize(columns: Int, rows: Int) {
        emulator.resize(columns, rows)
        request = request?.copy(columns = columns, rows = rows)
        bump()
        val live = transport ?: return
        scope.launch { live.resize(columns, rows) }
    }

    fun close() {
        val live = transport
        transport = null
        request = null
        redial?.cancel()
        redial = null
        reader?.cancel()
        reader = null
        pump?.cancel()
        pump = null
        _state.value = TerminalState()
        emulator.reset()
        if (live != null) scope.launch { live.close() }
    }

    private fun bump() {
        _state.value = _state.value.copy(revision = _state.value.revision + 1)
    }

    /** A dim line in the emulator, outside the shell */
    private fun notice(notice: Notice) {
        emulator.feed("\r\n\u001B[2m[${notices(notice)}]\u001B[0m\r\n".toByteArray())
        bump()
    }

    private fun finish(reason: String?, unanswered: Boolean = false) {
        transport = null
        _state.value = TerminalState(
            isOpen = false,
            errorMessage = reason,
            revision = _state.value.revision + 1,
            noRouteAnswered = unanswered,
        )
    }

    companion object {
        /** Pauses between automatic reconnects */
        val RECONNECT_PAUSES_MS = listOf(1_000L, 3_000L, 8_000L, 15_000L)

        fun endpoint(
            deployment: Deployment,
            node: DeploymentNode,
            pin: (DeploymentNode) -> String?,
            appLogin: (DeploymentNode) -> TerminalLogin?,
        ): TerminalEndpoint {
            val parent = deployment.nodes.firstOrNull { it.id == node.routedThrough }
                ?: deployment.nodes.firstOrNull {
                    node.legacySlot == DeploymentNode.LegacySlot.HOME &&
                        it.legacySlot == DeploymentNode.LegacySlot.VPS
                }
            return TerminalEndpoint(
                host = node.endpoint.host,
                port = node.endpoint.port,
                pinnedHostKey = pin(node),
                parent = parent?.let { hop ->
                    val login = appLogin(hop) ?: return@let null
                    TerminalEndpoint.Hop(
                        host = hop.endpoint.host,
                        port = hop.endpoint.port,
                        pinnedHostKey = pin(hop),
                        login = login,
                    )
                },
            )
        }

        fun defaultUsername(node: DeploymentNode): String = node.endpoint.user
    }
}

/** What a terminal needs of a session, and no more */
interface TerminalTransport {
    val output: Flow<TerminalEvent>

    /** The route the shell is open on */
    val connectedRoute: TerminalEndpoint? get() = null
    suspend fun start(columns: Int, rows: Int)
    suspend fun send(data: ByteArray)
    suspend fun resize(columns: Int, rows: Int)
    suspend fun close()
}
