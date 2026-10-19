import Foundation
import ServerControl

/// The machine behind the demo server
struct DemoCommandRunner: SSHCommandRunner, RemoteFileBrowser {
    let containers: [String]
    /// Which demo machine this is
    let deploymentID: UUID

    private let latency = Duration.milliseconds(220)

    init(deployment: Deployment) {
        containers = deployment.installedServices.map { $0.id.rawValue }
        deploymentID = deployment.id
    }

    private let pending = PendingDetachedOutput()

    func run(_ command: String, feeding secret: String, on host: SSHHostID,
             timeout: Duration) async throws -> ExecResult {
        try await run(command, on: host, timeout: timeout)
    }

    func run(_ command: String, on host: SSHHostID, timeout: Duration) async throws -> ExecResult {
        try? await Task.sleep(for: latency)
        let text = await DemoFleetState.shared.respond(to: command, on: host,
                                                       deployment: deploymentID,
                                                       containers: containers)
        if command.contains(DetachedJobs.exitMarker), command.contains("$DETACH") {
            await pending.store(text)
            return ExecResult(exitCode: 0, stdout: "", stderr: "")
        }
        return ExecResult(exitCode: 0, stdout: text, stderr: "")
    }

    func stream(_ command: String, on host: SSHHostID, timeout: Duration) -> AsyncThrowingStream<ExecChunk, Error> {
        AsyncThrowingStream { continuation in
            let latency = latency
            let id = deploymentID
            let containers = containers
            let pending = pending
            Task {
                try? await Task.sleep(for: latency)
                if command.contains(DetachedJobs.exitMarker),
                   let replay = await pending.take() {
                    continuation.yield(.stdout(replay))
                    continuation.yield(.stdout("\n\(DetachedJobs.exitMarker)0\n"))
                    continuation.finish()
                    return
                }
                let text = await DemoFleetState.shared.respond(to: command, on: host,
                                                               deployment: id,
                                                               containers: containers)
                continuation.yield(.stdout(text))
                continuation.finish()
            }
        }
    }

    func fireAndForget(_ command: String, on host: SSHHostID) async throws {
        _ = await DemoFleetState.shared.respond(to: command, on: host,
                                                deployment: deploymentID,
                                                containers: containers)
    }

    func disconnect() async {}

    // MARK: - Files

    func homeDirectory(on host: SSHHostID) async throws -> String { "/home/server-user" }

    func listDirectory(_ path: String, on host: SSHHostID) async throws -> [RemoteFileEntry] {
        try? await Task.sleep(for: latency)
        let now = Date()
        switch path {
        case "/home/server-user":
            return [entry("backups", in: path, kind: .directory, modified: now.addingTimeInterval(-3600)),
                    entry("docker", in: path, kind: .directory, modified: now.addingTimeInterval(-86_400)),
                    entry("install-report.txt", in: path, size: 2_048, modified: now.addingTimeInterval(-604_800))]
        case "/home/server-user/backups":
            return [entry("vaultwarden-2026-08-16.tar.gz", in: path, size: 4_812_544, modified: now.addingTimeInterval(-7200)),
                    entry("nextcloud-2026-08-16.tar.gz", in: path, size: 918_235_136, modified: now.addingTimeInterval(-9000))]
        default:
            return []
        }
    }

    func downloadFile(_ path: String, on host: SSHHostID, maxBytes: UInt64) async throws -> Data {
        try? await Task.sleep(for: latency)
        return Data(DemoFleetState.installReport.utf8)
    }

    func uploadFile(_ data: Data, to path: String, on host: SSHHostID) async throws {
        try? await Task.sleep(for: latency)
    }

    func deleteFile(_ entry: RemoteFileEntry, on host: SSHHostID) async throws {
        try? await Task.sleep(for: latency)
    }

    private func entry(_ name: String, in directory: String,
                       kind: RemoteFileEntry.Kind = .file,
                       size: UInt64? = nil, modified: Date) -> RemoteFileEntry {
        RemoteFileEntry(name: name, path: RemotePath.join(directory, name),
                        kind: kind, size: size, modified: modified)
    }

    // MARK: - Answers

    static var refusalMessage: String {
        UIL10n.string("This is the demo server: it shows how everything looks, but nothing is changed on a real machine.")
    }
}

private actor PendingDetachedOutput {
    private var text: String?

    func store(_ value: String) { text = value }

    func take() -> String? {
        defer { text = nil }
        return text
    }
}
