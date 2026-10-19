package com.skaymer.gryonixnexus.servercontrol

/** Errors surfaced by the dashboard logic */
sealed class ServerControlError(message: String) : Exception(message) {
    /** Dashboard settings or app SSH identity are missing or incomplete */
    data class NotConfigured(val detail: String) :
        ServerControlError("Dashboard is not configured: $detail")

    data class ConnectionFailed(val detail: String) :
        ServerControlError("SSH connection failed: $detail")

    data class Timeout(val command: String) :
        ServerControlError("Command timed out: $command")

    data class CommandFailed(val command: String, val exitCode: Int?, val stderr: String) :
        ServerControlError("Command failed (exit ${exitCode ?: "?"}): $command\n$stderr")

    data class SudoPasswordRequired(val command: String) : ServerControlError(
        "The server does not allow this action without a sudo password. Check this account's permissions for the action.",
    )

    data class ParseFailure(val command: String, val detail: String) :
        ServerControlError("Could not parse output of $command: $detail")

    data class HostKeyMismatch(val host: String) :
        ServerControlError("Host key changed for $host. Verify the server and re-pin the key in Settings.")

    /** SFTP downloads are held in memory — oversized files are refused */
    data class FileTooLarge(val path: String, val size: Long, val limit: Long) :
        ServerControlError("File $path is too large to transfer ($size bytes, limit $limit).")

    data object InstallUnfollowable : ServerControlError(
        "Lost the connection to the installation log. The installation itself keeps running " +
            "on the server — reopen it when the connection is back to pick the log up again.",
    )

    companion object {
        fun commandFailure(command: String, exitCode: Int?, stderr: String): ServerControlError =
            if (stderrAsksForASudoPassword(stderr)) {
                SudoPasswordRequired(command)
            } else {
                CommandFailed(command, exitCode, stderr)
            }

        /** sudo's exact wording when NOPASSWD does not cover the command */
        fun stderrAsksForASudoPassword(stderr: String): Boolean =
            stderr.contains("sudo: a password is required") ||
                stderr.contains("terminal is required to read the password") ||
                stderr.contains("interactive authentication is required")
    }
}
