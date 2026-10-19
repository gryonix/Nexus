import Foundation
import MailRecipe
import ServerControl

/// The machine a demo installation runs on
struct DemoInstallRunner: SSHCommandRunner, RemoteFileBrowser {
    let deployment: Deployment

    private let latency = Duration.milliseconds(140)
    private let script = DemoInstallScript()

    func run(_ command: String, on host: SSHHostID, timeout: Duration) async throws -> ExecResult {
        try? await Task.sleep(for: latency)
        if command.contains("GRYONIXNEXUS_PING") {
            // An empty id, so any script is accepted
            return ExecResult(exitCode: 0,
                              stdout: "GRYONIXNEXUS_PING\n\(SetupMarkers.distribution)::\n\(SudoAccess.readyToken)",
                              stderr: "")
        }
        return ExecResult(exitCode: 0, stdout: "", stderr: "")
    }

    func run(_ command: String, feeding secret: String, on host: SSHHostID,
             timeout: Duration) async throws -> ExecResult {
        try? await Task.sleep(for: latency)
        await script.store(secret)
        return ExecResult(exitCode: 0, stdout: "", stderr: "")
    }

    func stream(_ command: String, on host: SSHHostID,
                timeout: Duration) -> AsyncThrowingStream<ExecChunk, Error> {
        guard command.contains(SetupProgressParser.exitMarker) else {
            return AsyncThrowingStream { $0.finish() }
        }
        let script = script
        let services = deployment.installedServices.map(\.displayName)
        let domain = deployment.domain
        return AsyncThrowingStream { continuation in
            let task = Task {
                let text = await script.text
                let lines = DemoInstallLog.lines(script: text, services: services, domain: domain)
                for line in lines {
                    try? await Task.sleep(for: .milliseconds(line.delay))
                    if Task.isCancelled { break }
                    continuation.yield(.stdout(line.text + "\n"))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func fireAndForget(_ command: String, on host: SSHHostID) async throws {}

    func disconnect() async {}

    // MARK: - Files

    func homeDirectory(on host: SSHHostID) async throws -> String { "/root" }

    func listDirectory(_ path: String, on host: SSHHostID) async throws -> [RemoteFileEntry] { [] }

    func downloadFile(_ path: String, on host: SSHHostID, maxBytes: UInt64) async throws -> Data {
        Data()
    }

    func uploadFile(_ data: Data, to path: String, on host: SSHHostID) async throws {}

    func deleteFile(_ entry: RemoteFileEntry, on host: SSHHostID) async throws {}
}

/// The script the app uploaded
actor DemoInstallScript {
    private(set) var text = ""

    func store(_ script: String) { text = script }
}
