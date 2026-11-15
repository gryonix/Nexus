import Foundation

/// A script run detached, read back across reconnects
public enum DetachedScript {
    /// Runs the script from a temporary file, removed afterwards
    public static func command(for script: String, elevated: Bool) -> String {
        let encoded = Data(script.utf8).base64EncodedString()
        let elevate = elevated ? "sudo -n " : ""
        return "f=\"$(mktemp)\" && printf '%s' '\(encoded)' | base64 -d > \"$f\" && "
            + "( \(elevate)bash \"$f\"; rc=$?; rm -f \"$f\"; exit $rc )"
    }

    /// Everything the script printed
    public static func output(of script: String, elevated: Bool, subject: String,
                              on host: SSHHostID, runner: any SSHCommandRunner,
                              quickTimeout: Duration = .seconds(30),
                              runTimeout: Duration = .seconds(900)) async throws -> String {
        let box = OutputBox()
        try await DetachedJobs.run(command(for: script, elevated: elevated), kind: .measure, subject: subject,
                                   on: host, runner: runner, quickTimeout: quickTimeout,
                                   runTimeout: runTimeout) { box.append($0) }
        return box.text
    }
}
