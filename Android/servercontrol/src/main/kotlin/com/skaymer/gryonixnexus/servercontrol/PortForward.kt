package com.skaymer.gryonixnexus.servercontrol

import kotlinx.serialization.Serializable

/** A saved local-to-remote port forward for one server */
@Serializable
data class PortForward(
    val id: String,
    val deploymentID: String,
    val name: String = "",
    /** Port opened on this device */
    val localPort: Int,
    /** Host as the server sees it */
    val remoteHost: String = "localhost",
    val remotePort: Int,
) {
    enum class Problem { LOCAL_PORT, REMOTE_HOST, REMOTE_PORT, DUPLICATE_LOCAL_PORT }

    val title: String get() = name.ifEmpty { "$localPort → $remoteHost:$remotePort" }

    val summary: String get() = "127.0.0.1:$localPort → $remoteHost:$remotePort"

    fun problems(others: List<PortForward>): List<Problem> = buildList {
        if (!validPort(localPort)) add(Problem.LOCAL_PORT)
        val host = remoteHost.trim()
        if (host.isEmpty() || host.any { it.isWhitespace() || it == '\'' || it == '"' }) add(Problem.REMOTE_HOST)
        if (!validPort(remotePort, allowPrivileged = true)) add(Problem.REMOTE_PORT)
        if (others.any { it.id != id && it.localPort == localPort }) add(Problem.DUPLICATE_LOCAL_PORT)
    }

    companion object {
        /** Unprivileged ports only */
        fun validPort(port: Int, allowPrivileged: Boolean = false): Boolean =
            port >= (if (allowPrivileged) 1 else 1024) && port <= 65535
    }
}

/** Live state of one forward */
sealed interface PortForwardState {
    data object Stopped : PortForwardState
    data object Starting : PortForwardState
    data class Running(val connections: Int) : PortForwardState
    data class Failed(val message: String) : PortForwardState

    val isActive: Boolean get() = this is Starting || this is Running
}

/** Edits on the saved list */
object PortForwardList {
    fun forServer(id: String, all: List<PortForward>): List<PortForward> = all.filter { it.deploymentID == id }

    fun upserting(forward: PortForward, all: List<PortForward>): List<PortForward> =
        if (all.any { it.id == forward.id }) all.map { if (it.id == forward.id) forward else it } else all + forward

    fun removing(id: String, all: List<PortForward>): List<PortForward> = all.filter { it.id != id }

    fun removingServer(id: String, all: List<PortForward>): List<PortForward> =
        all.filter { it.deploymentID != id }
}
