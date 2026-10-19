package com.skaymer.gryonixnexus.servercontrol

import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/** Gives a non-root sign-in passwordless sudo, asking its password once */
object SudoAccess {
    const val READY_TOKEN = "GRYONIXNEXUS_SUDO_OK"

    /** Prints the token when root or passwordless sudo works */
    const val PROBE_COMMAND =
        "if [ \"\$(id -u)\" = 0 ] || sudo -n true 2>/dev/null; then echo $READY_TOKEN; fi"

    const val PASSWORD_MARKER = "GRYONIXNEXUS_PASSWORD="

    fun probeCommand(allowing: String): String =
        "if [ \"\$(id -u)\" = 0 ] || sudo -n true 2>/dev/null" +
            " || sudo -n -l ${ShellQuoting.singleQuoted(allowing)} >/dev/null 2>&1; then echo $READY_TOKEN; fi; " +
            "LC_ALL=C passwd -S 2>/dev/null | awk '{print \"$PASSWORD_MARKER\" \$2}'"

    /** The account has no password sudo could ever accept */
    fun passwordIsLocked(output: String): Boolean =
        output.lineSequence().map { it.trim() }.any {
            it.startsWith(PASSWORD_MARKER) && it.removePrefix(PASSWORD_MARKER) in setOf("L", "LK", "NP")
        }

    sealed interface Outcome {
        data object Granted : Outcome
        data object WrongPassword : Outcome

        /** The account is not an administrator at all */
        data object NotAllowed : Outcome
        data class Failed(val detail: String) : Outcome
    }

    fun isReady(output: String): Boolean =
        output.lineSequence().any { it.trim() == READY_TOKEN }

    /** A private 0700 directory for the password file */
    internal const val STAGING_COMMAND = "umask 077 && mktemp -d"

    /** Writes the sudoers drop-in as root, then wipes the password */
    internal fun grantCommand(directory: String): String {
        val dir = ShellQuoting.singleQuoted(directory)
        val script = listOf(
            "set -e",
            "u=\"\${SUDO_USER:?}\"",
            "n=\$(printf %s \"\$u\" | tr -c 'A-Za-z0-9_-' _)",
            "t=/etc/sudoers.d/.gryonixnexus-\$n.tmp",
            "printf '%s ALL=(ALL) NOPASSWD:ALL\\n' \"\$u\" > \"\$t\"",
            "chmod 440 \"\$t\"",
            "visudo -cf \"\$t\" >/dev/null || { rm -f \"\$t\"; exit 3; }",
            "mv \"\$t\" /etc/sudoers.d/gryonixnexus-\$n",
            "echo $READY_TOKEN",
        ).joinToString("; ")
        return "LC_ALL=C sudo -S -p '' sh -c ${ShellQuoting.singleQuoted(script)} < $dir/p; " +
            "rc=\$?; rm -rf $dir; exit \$rc"
    }

    internal fun outcome(result: ExecResult): Outcome {
        if (result.exitCode == 0 && isReady(result.stdout)) return Outcome.Granted
        val text = result.stderr
        if ("not in the sudoers file" in text || "not allowed to run sudo" in text) {
            return Outcome.NotAllowed
        }
        if ("incorrect password" in text || "Sorry, try again" in text ||
            "no password was provided" in text || isSudoRefusal(result)
        ) {
            return Outcome.WrongPassword
        }
        return Outcome.Failed(OutputTail.tail((text + result.stdout).trim(), 400))
    }

    /** sudo refused, also when it prints an insult */
    private fun isSudoRefusal(result: ExecResult): Boolean {
        val lines = result.stderr.lines().map { it.trim() }.filter { it.isNotEmpty() }
        return result.exitCode == 1 && lines.isNotEmpty() && lines.all { it.startsWith("sudo:") }
    }

    /** The password travels by SFTP, never in a command line */
    suspend fun grant(
        password: String,
        runner: SSHCommandRunner,
        files: RemoteFileBrowser,
        host: SSHHostID,
        timeout: Duration = 30.seconds,
    ): Outcome {
        val staged = runner.run(STAGING_COMMAND, host, timeout)
        val directory = staged.stdout.trim()
        if (staged.exitCode != 0 || !directory.startsWith("/") || '\n' in directory) {
            return Outcome.Failed(staged.stderr.trim())
        }
        try {
            files.uploadFile("$password\n".toByteArray(), "$directory/p", host)
        } catch (failure: Exception) {
            if (failure is CancellationException) throw failure
            runCatching { runner.run("rm -rf ${ShellQuoting.singleQuoted(directory)}", host, timeout) }
            throw failure
        }
        val result = try {
            runner.run(grantCommand(directory), host, timeout)
        } catch (error: Throwable) {
            runCatching { runner.run("rm -rf ${ShellQuoting.singleQuoted(directory)}", host, timeout) }
            throw error
        }
        return outcome(result)
    }
}
