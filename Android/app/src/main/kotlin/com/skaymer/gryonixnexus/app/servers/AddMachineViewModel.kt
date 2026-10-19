package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.addingNode
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.NodeCapability
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import java.util.UUID
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the add-a-machine screen is showing */
data class AddMachineState(
    val isChecking: Boolean = false,
    /** The node the check actually PROVED */
    val proved: DeploymentNode? = null,
    val errorMessage: String? = null,
)

/** Adds a machine to a deployment that already exists */
class AddMachineViewModel(
    private val scope: CoroutineScope,
    private val trialRunners: (Deployment) -> SSHCommandRunner,
    private val rememberPassword: (Deployment, DeploymentNode, String) -> Unit = { _, _, _ -> },
    private val persist: (Deployment) -> Unit = {},
) {
    private val _state = MutableStateFlow(AddMachineState())
    val state: StateFlow<AddMachineState> = _state.asStateFlow()

    companion object {
        const val MARKER = "GRYONIXNEXUS_NODE_OK"

        fun candidate(
            address: String,
            port: String,
            user: String,
            name: String,
            routedThrough: String?,
            id: String = UUID.randomUUID().toString(),
        ) = DeploymentNode(
            id = id,
            name = name.trim(),
            endpoint = HostEndpoint(
                host = address.trim(),
                port = port.trim().toIntOrNull() ?: 22,
                user = user.trim(),
            ),
            capabilities = setOf(NodeCapability.WORKER),
            routedThrough = routedThrough,
        )

        /** Enough typed in to be worth dialling */
        fun canCheck(
            address: String,
            user: String,
            password: String = "",
            needsPassword: Boolean = false,
        ): Boolean {
            if (address.trim().isEmpty() || user.trim().isEmpty()) return false
            return !needsPassword || password.isNotEmpty()
        }

        /** Whether this deployment signs in with a password at all */
        fun needsPassword(deployment: Deployment): Boolean = deployment.usesPasswordAuth
    }

    fun check(deployment: Deployment, node: DeploymentNode, password: String = "") {
        scope.launch {
            _state.value = AddMachineState(isChecking = true)
            val trial = try {
                deployment.addingNode(node)
            } catch (refusal: Exception) {
                _state.value = AddMachineState(errorMessage = refusal.message)
                return@launch
            }
            if (password.isNotEmpty() && needsPassword(deployment)) {
                rememberPassword(trial, node, password)
            }
            val runner = trialRunners(trial)
            try {
                val result = runner.run("echo $MARKER", node.sshHost, 25.seconds)
                _state.value = if (result.stdout.contains(MARKER)) {
                    AddMachineState(proved = node)
                } else {
                    AddMachineState(errorMessage = "The server connected but did not answer as expected.")
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                _state.value = AddMachineState(
                    errorMessage = failure.message ?: failure::class.simpleName,
                )
            } finally {
                runner.disconnect()
            }
        }
    }

    /** Writes the machine the check proved, and nothing else */
    fun add(deployment: Deployment): Boolean {
        val node = _state.value.proved ?: return false
        return try {
            persist(deployment.addingNode(node))
            _state.value = AddMachineState()
            true
        } catch (refusal: Exception) {
            _state.value = _state.value.copy(errorMessage = refusal.message)
            false
        }
    }

    fun reset() {
        _state.value = AddMachineState()
    }
}
