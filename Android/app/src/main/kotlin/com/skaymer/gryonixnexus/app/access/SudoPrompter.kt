package com.skaymer.gryonixnexus.app.access

import com.skaymer.gryonixnexus.servercontrol.RemoteFileBrowser
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.SudoAccess
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Why the last password did not work */
sealed interface SudoProblem {
    data object WrongPassword : SudoProblem
    data class Failed(val detail: String) : SudoProblem
}

/** One password question at a time, answered by a dialog */
class SudoPrompter {
    data class Question(val username: String, val problem: SudoProblem?)

    private val _question = MutableStateFlow<Question?>(null)
    val question: StateFlow<Question?> = _question.asStateFlow()
    private var pending: CompletableDeferred<String?>? = null

    suspend fun ask(username: String, problem: SudoProblem?): String? {
        val answer = CompletableDeferred<String?>()
        pending = answer
        _question.value = Question(username, problem)
        return try {
            answer.await()
        } finally {
            _question.value = null
            pending = null
        }
    }

    fun answer(password: String?) {
        pending?.complete(password)
    }
}

/** Makes sudo passwordless before work that needs it */
object SudoReadiness {
    class Declined : Exception("Administrator access was not set up, so the agent was not installed.")

    class PasswordLocked(user: String) : Exception(
        "$user has no password: the app locked it when it set up this server, so no password " +
            "can unlock sudo for it. Install the agent while signed in as root or as an account with sudo.",
    )

    class NotAdministrator : Exception(
        "This account may not act as administrator on the server. " +
            "Sign in as root or as an account that may use sudo.",
    )

    suspend fun ensure(
        runner: SSHCommandRunner,
        files: RemoteFileBrowser,
        host: SSHHostID,
        username: String,
        prompter: SudoPrompter,
        allowing: String? = null,
    ) {
        val command = allowing?.let { SudoAccess.probeCommand(it) } ?: SudoAccess.PROBE_COMMAND
        val probe = runner.run(command, host, 20.seconds)
        if (SudoAccess.isReady(probe.stdout)) return
        if (SudoAccess.passwordIsLocked(probe.stdout)) throw PasswordLocked(username)
        var problem: SudoProblem? = null
        while (true) {
            val password = prompter.ask(username, problem) ?: throw Declined()
            when (val outcome = SudoAccess.grant(password, runner, files, host)) {
                SudoAccess.Outcome.Granted -> return
                SudoAccess.Outcome.WrongPassword -> problem = SudoProblem.WrongPassword
                SudoAccess.Outcome.NotAllowed -> throw NotAdministrator()
                is SudoAccess.Outcome.Failed -> problem = SudoProblem.Failed(outcome.detail)
            }
        }
    }
}
