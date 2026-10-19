import Foundation

/// Errors surfaced by the dashboard logic
public enum ServerControlError: Error, Sendable, Equatable {
    /// Dashboard settings or app SSH identity are missing/incomplete
    case notConfigured(String)
    case connectionFailed(String)
    case timeout(command: String)
    case commandFailed(command: String, exitCode: Int32?, stderr: String)
    case sudoPasswordRequired(command: String)
    case parseFailure(command: String, detail: String)
    case hostKeyMismatch(host: String)
    /// SFTP downloads are held in memory — oversized files are refused
    case fileTooLarge(path: String, size: UInt64, limit: UInt64)
    case installUnfollowable
}

extension ServerControlError {
    public static func commandFailure(command: String, exitCode: Int32?,
                                      stderr: String) -> ServerControlError {
        if stderrAsksForASudoPassword(stderr) {
            return .sudoPasswordRequired(command: command)
        }
        return .commandFailed(command: command, exitCode: exitCode, stderr: stderr)
    }

    /// sudo's exact wording when NOPASSWD does not cover the command
    public static func stderrAsksForASudoPassword(_ stderr: String) -> Bool {
        stderr.contains("sudo: a password is required")
            || stderr.contains("terminal is required to read the password")
            || stderr.contains("interactive authentication is required")
    }
}

extension ServerControlError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured(let detail):
            return "Dashboard is not configured: \(detail)"
        case .connectionFailed(let detail):
            return "SSH connection failed: \(detail)"
        case .timeout(let command):
            return "Command timed out: \(command)"
        case .commandFailed(let command, let exitCode, let stderr):
            let code = exitCode.map(String.init) ?? "?"
            return "Command failed (exit \(code)): \(command)\n\(stderr)"
        case .sudoPasswordRequired:
            // The app substitutes a localized message; this is the fallback.
            return "The server does not allow this action without a sudo password. Check this account's permissions for the action."
        case .parseFailure(let command, let detail):
            return "Could not parse output of \(command): \(detail)"
        case .hostKeyMismatch(let host):
            return "Host key changed for \(host). Verify the server and re-pin the key in Settings."
        case .fileTooLarge(let path, let size, let limit):
            return "File \(path) is too large to transfer (\(size) bytes, limit \(limit))."
        case .installUnfollowable:
            // The app substitutes a localized message; this is the fallback.
            return "Lost the connection to the installation log. The installation itself keeps running on the server — reopen it when the connection is back to pick the log up again."
        }
    }
}
