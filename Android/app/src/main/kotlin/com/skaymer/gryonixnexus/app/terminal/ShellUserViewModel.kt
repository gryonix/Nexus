package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.ShellUserCommand
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ShellUserState(
    val busy: Boolean = false,
    val created: String? = null,
    /** Everything the server said, verbatim — see [create] */
    val failure: String? = null,
)

class ShellUserViewModel(
    private val scope: CoroutineScope,
    /** This deployment's own public key, from the device's secret store */
    private val publicKey: (Deployment) -> String = { "" },
    private val runner: suspend (Deployment) -> SSHCommandRunner = { error("no session") },
) {
    private val _state = MutableStateFlow(ShellUserState())
    val state: StateFlow<ShellUserState> = _state.asStateFlow()

    fun reset() {
        _state.value = ShellUserState()
    }

    /** Runs the creation and reports what happened */
    fun create(deployment: Deployment, name: String, sudo: Boolean) {
        scope.launch {
            _state.value = ShellUserState(busy = true)
            try {
                val key = publicKey(deployment)
                if (key.isEmpty()) {
                    _state.value = ShellUserState(failure = "no key for this server")
                    return@launch
                }
                val command = ShellUserCommand.command(name, key, sudo)
                if (command == null) {
                    _state.value = ShellUserState(failure = "that name cannot be used")
                    return@launch
                }
                val result = runner(deployment).run(
                    command,
                    deployment.servicesHost,
                    deployment.dashboardConfig.restartTimeout,
                )
                val text = (result.stdout + "\n" + result.stderr).trim()
                _state.value = if (text.contains(ShellUserCommand.MARKER)) {
                    ShellUserState(created = name)
                } else {
                    ShellUserState(failure = text.ifEmpty { "the server did not confirm the account" })
                }
            } catch (error: Throwable) {
                _state.value = ShellUserState(failure = error.message ?: error::class.simpleName)
            }
        }
    }
}
