package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.transport.TerminalEndpoint
import com.skaymer.gryonixnexus.transport.TerminalEvent
import com.skaymer.gryonixnexus.transport.TerminalLogin
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
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
)

class TerminalViewModel(
    private val scope: CoroutineScope,
    private val sessions: (TerminalEndpoint, TerminalLogin) -> TerminalTransport,
) {
    private val _state = MutableStateFlow(TerminalState())
    val state: StateFlow<TerminalState> = _state.asStateFlow()

    val emulator = TerminalEmulator()

    private var transport: TerminalTransport? = null
    private var pump: Job? = null

    /** Open a shell */
    fun open(
        endpoint: TerminalEndpoint,
        login: TerminalLogin,
        columns: Int,
        rows: Int,
    ) {
        if (transport != null || _state.value.isConnecting) return
        emulator.reset()
        emulator.resize(columns, rows)
        _state.value = TerminalState(isConnecting = true)
        pump = scope.launch {
            val live = sessions(endpoint, login)
            transport = live
            val reading = launch {
                live.output.collect { event ->
                    when (event) {
                        is TerminalEvent.Output -> {
                            emulator.feed(event.bytes)
                            bump()
                        }
                        is TerminalEvent.Closed -> finish(event.reason)
                    }
                }
            }
            try {
                live.start(columns, rows)
                _state.value = TerminalState(isOpen = true, revision = _state.value.revision + 1)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                reading.cancel()
                transport = null
                finish(failure.message ?: failure::class.simpleName)
            }
        }
    }

    fun send(data: ByteArray) {
        val live = transport ?: return
        scope.launch { live.send(data) }
    }

    fun resize(columns: Int, rows: Int) {
        emulator.resize(columns, rows)
        bump()
        val live = transport ?: return
        scope.launch { live.resize(columns, rows) }
    }

    fun close() {
        val live = transport
        transport = null
        pump?.cancel()
        pump = null
        _state.value = TerminalState()
        emulator.reset()
        if (live != null) scope.launch { live.close() }
    }

    private fun bump() {
        _state.value = _state.value.copy(revision = _state.value.revision + 1)
    }

    private fun finish(reason: String?) {
        transport = null
        _state.value = TerminalState(
            isOpen = false,
            errorMessage = reason,
            revision = _state.value.revision + 1,
        )
    }

    companion object {
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
    suspend fun start(columns: Int, rows: Int)
    suspend fun send(data: ByteArray)
    suspend fun resize(columns: Int, rows: Int)
    suspend fun close()
}
