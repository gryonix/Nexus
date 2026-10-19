import Foundation
import ServerControl

public struct SSHMoveShell: ServiceMoveShell {
    private let runner: any SSHCommandRunner
    private let host: SSHHostID
    public let loginUser: String

    public init(runner: any SSHCommandRunner, host: SSHHostID, loginUser: String) {
        self.runner = runner
        self.host = host
        self.loginUser = loginUser
    }

    public func appendAuthorizedKey(_ line: String) async throws {
        let quoted = ShellQuoting.singleQuoted(line)
        try await run("umask 077; mkdir -p ~/.ssh && printf '%s\\n' \(quoted) >> ~/.ssh/authorized_keys"
            + " && chmod 600 ~/.ssh/authorized_keys")
    }

    public func removeAuthorizedKeys(containing marker: String) async throws {
        let quoted = ShellQuoting.singleQuoted(marker)
        try await run("f=~/.ssh/authorized_keys; [ -f \"$f\" ] || exit 0; t=$(mktemp) || exit 1;"
            + " grep -vF -- \(quoted) \"$f\" > \"$t\"; cat \"$t\" > \"$f\"; rm -f \"$t\"")
    }

    private func run(_ command: String) async throws {
        let result = try await runner.run(command, on: host, timeout: .seconds(30))
        guard result.succeeded else {
            throw ServerControlError.commandFailed(command: "authorized_keys", exitCode: result.exitCode,
                                                   stderr: result.stderr)
        }
    }
}
