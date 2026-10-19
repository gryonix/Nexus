import Foundation
import MailRecipe
import ServerControl

struct AgentBootstrapOperations {
    static let archiveName = AgentBootstrapSections.archiveName
    static let wrapperPath = AgentBootstrapSections.scriptPath

    enum BootstrapError: LocalizedError {
        case sourcesMissing

        var errorDescription: String? {
            switch self {
            case .sourcesMissing:
                return UIL10n.string("This build of the app does not carry the agent sources.")
            }
        }
    }

    /// The version of the archive this build carries
    static var shippedVersion: String {
        guard let url = Bundle.main.url(forResource: "agent-src", withExtension: "version"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return AgentBootstrapSections.bundledVersion
        }
        let version = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? AgentBootstrapSections.bundledVersion : version
    }

    /// The archive and the constant disagree
    static var shippedVersionIsStale: Bool {
        shippedVersion != AgentBootstrapSections.bundledVersion
    }

    /// The agent source tree this build carries
    static func sourceArchive() throws -> Data {
        guard let url = Bundle.main.url(forResource: "agent-src", withExtension: "tar.gz"),
              let data = try? Data(contentsOf: url) else {
            throw BootstrapError.sourcesMissing
        }
        return data
    }

    static func install(runner: any SSHCommandRunner & RemoteFileBrowser,
                        host: SSHHostID,
                        source: AgentSource = .app,
                        reinstall: Bool = false,
                        onPhase: @escaping @Sendable (String) -> Void,
                        onOutput: @escaping @Sendable (String) -> Void) async throws {
        let home = try await runner.homeDirectory(on: host)
        let build = DetachedAgentBuild(home: home)
        if try await build.isRunning(runner: runner, host: host) {
            onPhase(UIL10n.string("The server is already building the agent. Following it…"))
            try await finish(build, prefix: nil, runner: runner, host: host, onPhase: onPhase, onOutput: onOutput)
            return
        }
        if reinstall {
            let marker = "\(home)/\(AgentBootstrapSections.reinstallMarkerName)"
            _ = try await runner.run(": > \(ShellQuoting.singleQuoted(marker))", on: host, timeout: .seconds(20))
        }
        let remoteArchive = "\(home)/\(archiveName)"
        let prefix = try await stage(source, archivePath: remoteArchive, home: home, runner: runner,
                                     host: host, onPhase: onPhase, onOutput: onOutput)
        do {
            try await finish(build, prefix: prefix, runner: runner, host: host, onPhase: onPhase, onOutput: onOutput)
        } catch is WrapperMissing {
            onPhase(UIL10n.string("Preparing the server…"))
            try await installWrapper(runner: runner, host: host, archivePath: remoteArchive, home: home)
            try await finish(build, prefix: nil, runner: runner, host: host, onPhase: onPhase, onOutput: onOutput)
        } catch let mismatch as ArchiveElsewhere {
            onPhase(UIL10n.string("Putting the sources where the server expects them…"))
            onOutput(UIL10n.string("The server reads %@; the upload went to %@.", mismatch.expected, remoteArchive))
            let again = try await stage(source, archivePath: mismatch.expected, home: home, retry: true, runner: runner,
                                        host: host, onPhase: onPhase, onOutput: onOutput)
            try await finish(build, prefix: again, runner: runner, host: host, onPhase: onPhase, onOutput: onOutput)
        }
    }

    private static func stage(_ source: AgentSource, archivePath: String, home: String, retry: Bool = false,
                              runner: any SSHCommandRunner & RemoteFileBrowser, host: SSHHostID,
                              onPhase: @escaping @Sendable (String) -> Void,
                              onOutput: @escaping @Sendable (String) -> Void) async throws -> String? {
        let grace = await BackgroundGrace()
        defer { Task { @MainActor in grace.end() } }
        if let fetch = source.fetchScript(archivePath: archivePath) {
            onPhase(UIL10n.string("Sending the setup file to the server…"))
            onOutput(UIL10n.string("Agent sources: the repository."))
            let staged = "\(home)/.gryonixnexus-agent-fetch.sh"
            try await runner.uploadFile(Data((fetch + "\n").utf8), to: staged, on: host)
            return staged
        }
        onPhase(UIL10n.string("Sending the agent sources…"))
        onOutput(UIL10n.string("Agent sources: this app carries %1$@, going to %2$@.", shippedVersion, archivePath))
        do {
            try await runner.uploadFile(try sourceArchive(), to: archivePath, on: host)
        } catch let error as BootstrapError {
            throw error
        } catch {
            throw ServerControlError.notConfigured(retry
                ? UIL10n.string("The server looks for the agent sources in %@, and this account cannot write there. Connect as a user that can, or re-run the installation to refresh the server's wrapper.",
                                archivePath)
                : UIL10n.string("Could not write %@ on the server: %@", archivePath, error.localizedDescription))
        }
        return nil
    }

    private static func finish(_ build: DetachedAgentBuild, prefix: String?,
                               runner: any SSHCommandRunner & RemoteFileBrowser, host: SSHHostID,
                               onPhase: @escaping @Sendable (String) -> Void,
                               onOutput: @escaping @Sendable (String) -> Void) async throws {
        onPhase(UIL10n.string("The server is building the agent on its own. You can minimise the app: when you come back, it picks up the build where it is."))
        let running = prefix == nil ? try await build.isRunning(runner: runner, host: host) : false
        if !running {
            _ = try await runner.run(build.startCommand(fetchScript: prefix, wrapper: wrapperPath),
                                     on: host, timeout: .seconds(60))
        }
        let outcome = try await build.follow(runner: runner, host: host, onOutput: onOutput, onReconnect: { error in
            onPhase(UIL10n.string("The connection dropped; the server keeps building. Reconnecting…"))
            onOutput(UIL10n.string("Connection dropped: %@", error.localizedDescription))
        }, onReconnected: {
            onPhase(UIL10n.string("Connected again. The server is still building the agent."))
        })
        guard outcome.exitCode != 0 else { return }
        if let expected = expectedArchivePath(in: outcome.transcript) {
            throw ArchiveElsewhere(expected: expected)
        }
        if wrapperIsMissing(in: outcome.transcript) {
            throw WrapperMissing()
        }
        throw ServerControlError.notConfigured(
            UIL10n.string("The agent did not build on this server: %@",
                          tail(of: outcome.transcript, fallback: UIL10n.string("the build stopped without saying why"))))
    }

    /// Raised when the wrapper looked somewhere else for the archive
    private struct ArchiveElsewhere: Error {
        let expected: String
    }

    private struct WrapperMissing: Error {}

    private static func installWrapper(runner: any SSHCommandRunner & RemoteFileBrowser,
                                       host: SSHHostID,
                                       archivePath: String,
                                       home: String) async throws {
        let staged = "\(home)/.gryonixnexus-agent-bootstrap.sh"
        let script = AgentBootstrapSections.wrapperScript(archivePath: archivePath) + "\n"
        try await runner.uploadFile(Data(script.utf8), to: staged, on: host)
        let command = "sudo -n install -o root -g root -m 700 "
            + "\(ShellQuoting.singleQuoted(staged)) "
            + "\(ShellQuoting.singleQuoted(AgentBootstrapSections.scriptPath))"
        let result = try? await runner.run(command, on: host, timeout: .seconds(60))
        _ = try? await runner.run("rm -f \(ShellQuoting.singleQuoted(staged))",
                                  on: host, timeout: .seconds(30))
        guard let result, result.exitCode == 0 else {
            throw ServerControlError.notConfigured(
                UIL10n.string("This server has never been set up by the app, so it has no agent installer, and this account cannot create one in %@. Connect as a user that can run sudo, or install the server from the app first.",
                              AgentBootstrapSections.scriptPath))
        }
    }

    /// The last lines the server printed
    static func tail(of transcript: String, fallback: String) -> String {
        let lines = transcript.split(separator: "\n").map(String.init)
        guard !lines.isEmpty else { return fallback }
        return lines.suffix(8).joined(separator: "\n")
    }

    /// Whether the server answered "there is no such wrapper"
    static func wrapperIsMissing(in output: String) -> Bool {
        guard output.contains(AgentBootstrapSections.scriptPath) else { return false }
        return output.contains("command not found") || output.contains("No such file or directory")
    }

    static func expectedArchivePath(in output: String) -> String? {
        for line in output.split(separator: "\n") {
            guard let open = line.range(of: "no agent sources uploaded ("),
                  let close = line[open.upperBound...].firstIndex(of: ")") else { continue }
            let path = String(line[open.upperBound..<close])
            guard path.hasPrefix("/"), !path.contains(" ") else { continue }
            return path
        }
        return nil
    }
}
