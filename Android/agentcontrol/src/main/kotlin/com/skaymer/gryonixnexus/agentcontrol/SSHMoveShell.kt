package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import kotlin.time.Duration.Companion.seconds

class SSHMoveShell(
    private val runner: SSHCommandRunner,
    private val host: SSHHostID,
    override val loginUser: String,
) : ServiceMoveShell {
    override suspend fun appendAuthorizedKey(line: String) {
        run(
            "umask 077; mkdir -p ~/.ssh && printf '%s\\n' ${quoted(line)} >> ~/.ssh/authorized_keys" +
                " && chmod 600 ~/.ssh/authorized_keys",
        )
    }

    override suspend fun removeAuthorizedKeys(containing: String) {
        run(
            "f=~/.ssh/authorized_keys; [ -f \"\$f\" ] || exit 0; t=\$(mktemp) || exit 1;" +
                " grep -vF -- ${quoted(containing)} \"\$f\" > \"\$t\"; cat \"\$t\" > \"\$f\"; rm -f \"\$t\"",
        )
    }

    private suspend fun run(command: String) {
        val result = runner.run(command, host, 30.seconds)
        if (!result.succeeded) throw ServerControlError.CommandFailed("authorized_keys", result.exitCode, result.stderr)
    }

    private fun quoted(value: String): String = "'" + value.replace("'", "'\\''") + "'"
}
