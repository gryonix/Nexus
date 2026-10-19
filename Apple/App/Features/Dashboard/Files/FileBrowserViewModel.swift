import Foundation
import ServerControl
import SwiftUI

@MainActor
final class FileBrowserViewModel: ObservableObject {
    static let downloadLimit: UInt64 = 200 * 1024 * 1024

    let deployment: Deployment
    let host: SSHHostID

    @Published var path = "/"
    @Published var entries: [RemoteFileEntry] = []
    @Published var isLoading = false
    @Published var isTransferring = false
    @Published var errorMessage: String?
    @Published var pendingDownload: DownloadedFile?

    struct DownloadedFile: Identifiable {
        let id = UUID()
        let name: String
        let data: Data
    }

    private typealias FileSession = any SSHCommandRunner & RemoteFileBrowser
    private var session: FileSession?
    private let makeSession: @Sendable () throws -> FileSession

    init(deployment: Deployment, host: SSHHostID,
         makeSession: (@Sendable (Deployment) throws -> any SSHCommandRunner & RemoteFileBrowser)? = nil) {
        self.deployment = deployment
        self.host = host
        let factory = makeSession ?? { try DashboardSessionFactory.makeRunner(deployment: $0) }
        self.makeSession = { try factory(deployment) }
    }

    func start() async {
        guard entries.isEmpty, !isLoading else { return }
        await run {
            let session = try await self.connect()
            let home = try await session.homeDirectory(on: self.host)
            let chosen = ServerAccessStore.options(for: self.deployment.id).sftpDirectory?
                .trimmingCharacters(in: .whitespaces)
            if let chosen, !chosen.isEmpty, chosen != home {
                if let entries = try? await session.listDirectory(chosen, on: self.host) {
                    self.path = chosen
                    self.entries = entries
                    return
                }
            }
            self.path = home
            self.entries = try await session.listDirectory(home, on: self.host)
        }
    }

    func refresh() async {
        await run {
            let session = try await self.connect()
            self.entries = try await session.listDirectory(self.path, on: self.host)
        }
    }

    func open(_ entry: RemoteFileEntry) async {
        guard entry.kind == .directory else { return }
        await navigate(to: entry.path)
    }

    var isAtRoot: Bool { path == "/" }

    func goUp() async {
        guard !isAtRoot else { return }
        await navigate(to: RemotePath.parent(of: path))
    }

    func download(_ entry: RemoteFileEntry) async {
        guard entry.kind == .file || entry.kind == .symlink else { return }
        isTransferring = true
        errorMessage = nil
        let island = IslandRun(title: UIL10n.string("Downloading %@", entry.name),
                               serverName: deployment.name, progressText: entry.path)
        defer {
            isTransferring = false
            island.finish(errorMessage == nil ? UIL10n.string("Downloaded.") : "", error: errorMessage)
        }
        await run {
            let session = try await self.connect()
            let data = try await session.downloadFile(entry.path, on: self.host,
                                                      maxBytes: Self.downloadLimit)
            self.pendingDownload = DownloadedFile(name: entry.name, data: data)
        }
    }

    func upload(from url: URL) async {
        isTransferring = true
        errorMessage = nil
        let island = IslandRun(title: UIL10n.string("Uploading %@", url.lastPathComponent),
                               serverName: deployment.name, progressText: path)
        defer {
            isTransferring = false
            island.finish(errorMessage == nil ? UIL10n.string("Uploaded.") : "", error: errorMessage)
        }
        await run {
            let data = try await Self.readLocalFile(at: url, maxBytes: Self.downloadLimit)
            let session = try await self.connect()
            let target = RemotePath.join(self.path, url.lastPathComponent)
            try await session.uploadFile(data, to: target, on: self.host)
            self.entries = try await session.listDirectory(self.path, on: self.host)
        }
    }

    private static func readLocalFile(at url: URL, maxBytes: UInt64) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               UInt64(size) > maxBytes {
                throw ServerControlError.fileTooLarge(path: url.lastPathComponent,
                                                      size: UInt64(size), limit: maxBytes)
            }
            return try Data(contentsOf: url)
        }.value
    }

    func delete(_ entry: RemoteFileEntry) async {
        await run {
            let session = try await self.connect()
            try await session.deleteFile(entry, on: self.host)
            self.entries = try await session.listDirectory(self.path, on: self.host)
        }
    }

    func teardown() {
        session = nil
    }

    // MARK: - Internals

    private func navigate(to newPath: String) async {
        await run {
            let session = try await self.connect()
            let listing = try await session.listDirectory(newPath, on: self.host)
            self.path = newPath
            self.entries = listing
        }
    }

    private func connect() async throws -> FileSession {
        if let session { return session }
        let make = makeSession
        let fresh = try await Task.detached(priority: .userInitiated) { try make() }.value
        if let session {
            Task { [id = deployment.id] in
                await DashboardSessionFactory.release(fresh, deploymentID: id)
            }
            return session
        }
        session = fresh
        return fresh
    }

    private func run(_ body: @escaping () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await body()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }
}
