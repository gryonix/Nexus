import Foundation

/// Gives a non-root sign-in passwordless sudo, asking its password once
public enum SudoAccess {
    public static let readyToken = "GRYONIXNEXUS_SUDO_OK"

    /// Prints the token when root or passwordless sudo works
    public static let probeCommand =
        "if [ \"$(id -u)\" = 0 ] || sudo -n true 2>/dev/null; then echo \(readyToken); fi"

    public static let passwordMarker = "GRYONIXNEXUS_PASSWORD="

    public static func probeCommand(allowing command: String) -> String {
        "if [ \"$(id -u)\" = 0 ] || sudo -n true 2>/dev/null"
            + " || sudo -n -l \(ShellQuoting.singleQuoted(command)) >/dev/null 2>&1; then echo \(readyToken); fi; "
            + "LC_ALL=C passwd -S 2>/dev/null | awk '{print \"\(passwordMarker)\" $2}'"
    }

    /// The account has no password sudo could ever accept
    public static func passwordIsLocked(_ output: String) -> Bool {
        output.split(separator: "\n").contains { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix(passwordMarker) else { return false }
            return ["L", "LK", "NP"].contains(String(text.dropFirst(passwordMarker.count)))
        }
    }

    public enum Outcome: Equatable, Sendable {
        case granted
        case wrongPassword
        /// The account is not an administrator at all
        case notAllowed
        case failed(String)
    }

    public static func isReady(_ output: String) -> Bool {
        output.split(separator: "\n").contains {
            $0.trimmingCharacters(in: .whitespaces) == readyToken
        }
    }

    /// A private 0700 directory for the password file
    static let stagingCommand = "umask 077 && mktemp -d"

    /// Writes the sudoers drop-in as root, then wipes the password
    static func grantCommand(directory: String) -> String {
        let dir = ShellQuoting.singleQuoted(directory)
        let script = [
            "set -e",
            "u=\"${SUDO_USER:?}\"",
            "n=$(printf %s \"$u\" | tr -c 'A-Za-z0-9_-' _)",
            "t=/etc/sudoers.d/.gryonixnexus-$n.tmp",
            "printf '%s ALL=(ALL) NOPASSWD:ALL\\n' \"$u\" > \"$t\"",
            "chmod 440 \"$t\"",
            "visudo -cf \"$t\" >/dev/null || { rm -f \"$t\"; exit 3; }",
            "mv \"$t\" /etc/sudoers.d/gryonixnexus-$n",
            "echo \(readyToken)"
        ].joined(separator: "; ")
        return "LC_ALL=C sudo -S -p '' sh -c \(ShellQuoting.singleQuoted(script)) < \(dir)/p; "
            + "rc=$?; rm -rf \(dir); exit $rc"
    }

    static func outcome(of result: ExecResult) -> Outcome {
        if result.exitCode == 0, isReady(result.stdout) { return .granted }
        let text = result.stderr
        if text.contains("not in the sudoers file") || text.contains("not allowed to run sudo") {
            return .notAllowed
        }
        if text.contains("incorrect password") || text.contains("Sorry, try again")
            || text.contains("no password was provided") || isSudoRefusal(result) {
            return .wrongPassword
        }
        let detail = (text + result.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(OutputTail.tail(detail, maxCharacters: 400))
    }

    /// sudo refused, also when it prints an insult
    private static func isSudoRefusal(_ result: ExecResult) -> Bool {
        let lines = result.stderr.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return result.exitCode == 1 && !lines.isEmpty && lines.allSatisfy { $0.hasPrefix("sudo:") }
    }

    /// The password travels by SFTP, never in a command line
    public static func grant(password: String,
                             runner: any SSHCommandRunner & RemoteFileBrowser,
                             host: SSHHostID,
                             timeout: Duration = .seconds(30)) async throws -> Outcome {
        let staged = try await runner.run(stagingCommand, on: host, timeout: timeout)
        let directory = staged.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard staged.exitCode == 0, directory.hasPrefix("/"), !directory.contains("\n") else {
            return .failed(staged.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        do {
            try await runner.uploadFile(Data((password + "\n").utf8),
                                        to: directory + "/p", on: host)
        } catch {
            _ = try? await runner.run("rm -rf \(ShellQuoting.singleQuoted(directory))",
                                      on: host, timeout: timeout)
            throw error
        }
        let result: ExecResult
        do {
            result = try await runner.run(grantCommand(directory: directory), on: host, timeout: timeout)
        } catch {
            _ = try? await runner.run("rm -rf \(ShellQuoting.singleQuoted(directory))",
                                      on: host, timeout: timeout)
            throw error
        }
        return outcome(of: result)
    }
}
