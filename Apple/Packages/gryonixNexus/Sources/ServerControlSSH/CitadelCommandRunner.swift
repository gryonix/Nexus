import Citadel
import CryptoKit
import Foundation
import NIOCore
import NIOPosix
import ServerControl

/// Citadel-backed SSH transport
public actor CitadelCommandRunner: SSHCommandRunner {
    private let settings: SSHConnectionSettings
    private let onPinHostKey: @Sendable (SSHHostID, String) -> Void

    /// The live session per host
    private var clients: [SSHHostID: SSHClient] = [:]
    /// See `init` — pins a jump host's key on first sight
    private let onPinBastionHostKey: @Sendable (String, String) -> Void
    /// In-flight connection attempts, shared by every concurrent caller
    private var connecting: [SSHHostID: Task<SSHClient, Error>] = [:]
    private static let maxConcurrentChannels = 4
    private var activeChannels = 0
    /// Callers parked until a channel slot frees up
    private var channelWaiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

    private var directLinks: Set<SSHHostID> = []

    private var bastions: [String: SSHClient] = [:]

    private var fallbackLinks: Set<SSHHostID> = []

    /// Per-host keepalive tickers; see `startKeepalive`
    private var keepalives: [SSHHostID: Task<Void, Never>] = [:]
    /// How often the keepalive nudges an idle session
    private static let keepaliveInterval = Duration.seconds(60)

    public init(settings: SSHConnectionSettings,
                onPinHostKey: @escaping @Sendable (SSHHostID, String) -> Void = { _, _ in },
                onPinBastionHostKey: @escaping @Sendable (String, String) -> Void = { _, _ in }) {
        self.settings = settings
        self.onPinHostKey = onPinHostKey
        self.onPinBastionHostKey = onPinBastionHostKey
    }

    // MARK: - Keepalive

    private func startKeepalive(for host: SSHHostID, client: SSHClient) {
        keepalives[host]?.cancel()
        keepalives[host] = Task { [interval = Self.keepaliveInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { return }
                guard client.isConnected else { return }
                do {
                    _ = try await client.executeCommandStream("true")
                } catch let error as CitadelError where error == .channelCreationFailed {
                    await self.dropDeadLink(host, client)
                    return
                } catch {}
            }
        }
    }

    /// Forgets a link that stopped answering, if still current
    private func dropDeadLink(_ host: SSHHostID, _ client: SSHClient) async {
        guard clients[host] === client else { return }
        await reset(host)
    }

    private func stopKeepalive(for host: SSHHostID) {
        keepalives.removeValue(forKey: host)?.cancel()
    }

    // MARK: - SSHCommandRunner

    public func run(_ command: String, on host: SSHHostID, timeout: Duration) async throws -> ExecResult {
        try await withTimeout(timeout, command: command, host: host) { client in
            var stdout = ""
            var stderr = ""
            var outCarry = UTF8Carry()
            var errCarry = UTF8Carry()
            do {
                let stream = try await client.executeCommandStream(command)
                for try await chunk in stream {
                    switch chunk {
                    case .stdout(let buffer): stdout += outCarry.append(buffer)
                    case .stderr(let buffer): stderr += errCarry.append(buffer)
                    }
                }
                return ExecResult(exitCode: 0, stdout: stdout + outCarry.flush(),
                                  stderr: stderr + errCarry.flush())
            } catch let failure as SSHClient.CommandFailed {
                // Non-zero exit is a result, not a transport error.
                return ExecResult(exitCode: Int32(failure.exitCode), stdout: stdout + outCarry.flush(),
                                  stderr: stderr + errCarry.flush())
            }
        }
    }

    public nonisolated func stream(_ command: String, on host: SSHHostID,
                                   timeout: Duration) -> AsyncThrowingStream<ExecChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.pump(command, on: host, timeout: timeout, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func pump(_ command: String, on host: SSHHostID, timeout: Duration,
                      into continuation: AsyncThrowingStream<ExecChunk, Error>.Continuation) async throws {
        try await withTimeout(timeout, command: command, host: host) { client in
            var outCarry = UTF8Carry()
            var errCarry = UTF8Carry()
            let stream = try await client.executeCommandStream(command)
            for try await chunk in stream {
                switch chunk {
                case .stdout(let buffer):
                    let text = outCarry.append(buffer)
                    if !text.isEmpty { continuation.yield(.stdout(text)) }
                case .stderr(let buffer):
                    let text = errCarry.append(buffer)
                    if !text.isEmpty { continuation.yield(.stderr(text)) }
                }
            }
            let outRest = outCarry.flush()
            if !outRest.isEmpty { continuation.yield(.stdout(outRest)) }
            let errRest = errCarry.flush()
            if !errRest.isEmpty { continuation.yield(.stderr(errRest)) }
        }
    }

    public func fireAndForget(_ command: String, on host: SSHHostID) async throws {
        let client = try await client(for: host, patientJump: true)
        _ = try await client.executeCommandStream(command)
        await dropJumpedChildren(of: host, inBackground: true)
        await closeLink(host)
    }

    public func disconnect() async {
        for host in Array(clients.keys) {
            await closeLink(host)
        }
    }

    public func invalidate(_ host: SSHHostID) async {
        await closeLink(host)
    }

    /// The two-machine spelling of `invalidate(_:)`, kept for the probe tool
    public func invalidateHome() async {
        await invalidate(.home)
    }

    private func closeLink(_ host: SSHHostID) async {
        stopKeepalive(for: host)
        let live = clients.removeValue(forKey: host)
        directLinks.remove(host)
        try? await live?.close()
    }

    /// Drops the sessions that exist only INSIDE `parent`'s session
    private func dropJumpedChildren(of parent: SSHHostID, inBackground: Bool) async {
        for child in children(of: parent) where !directLinks.contains(child) {
            guard let stale = clients.removeValue(forKey: child) else { continue }
            stopKeepalive(for: child)
            if inBackground {
                Task { try? await stale.close() }
            } else {
                try? await stale.close()
            }
        }
    }

    func children(of parent: SSHHostID) -> [SSHHostID] {
        routableHosts.filter { route(to: $0)?.parent == parent }
    }

    var routableHosts: [SSHHostID] {
        [.vps, .home] + settings.additionalNodes.map { .node($0.id) }
    }

    /// Where a host lives and what it is reached through
    struct Route {
        let parent: SSHHostID?
        let address: Address
        /// Reachable without going through the parent at all
        let fallback: Address?

        struct Address {
            let host: String
            let port: Int
            let pin: String?
            var bastion: SSHConnectionSettings.Hop?

            init(host: String, port: Int, pin: String?,
                 bastion: SSHConnectionSettings.Hop? = nil) {
                self.host = host
                self.port = port
                self.pin = pin
                self.bastion = bastion
            }
        }
    }

    func route(to host: SSHHostID) -> Route? {
        switch host.kind {
        case .slot(.vps):
            return Route(parent: nil,
                         address: .init(host: settings.vpsHost, port: settings.vpsPort,
                                        pin: settings.pinnedVPSHostKey,
                                        bastion: settings.bastion),
                         fallback: settings.entryFallback.map {
                             .init(host: $0.host, port: $0.port,
                                   pin: settings.pinnedVPSHostKey,
                                   bastion: $0.bastion ?? settings.bastion)
                         })
        case .slot(.home):
            let lan = settings.homeLANHost.flatMap { $0.isEmpty ? nil : $0 }
            return Route(parent: .vps,
                         address: .init(host: settings.homeHost, port: settings.homePort,
                                        pin: settings.pinnedHomeHostKey),
                         fallback: lan.map { .init(host: $0, port: settings.homePort,
                                                   pin: settings.pinnedHomeHostKey) })
        case .node(let id):
            guard let node = settings.additionalNodes.first(where: { $0.id == id }) else { return nil }
            let lan = node.lanHost.flatMap { $0.isEmpty ? nil : $0 }
            return Route(parent: node.parent,
                         address: .init(host: node.host, port: node.port, pin: node.pinnedHostKey),
                         fallback: lan.map { .init(host: $0, port: node.port, pin: node.pinnedHostKey) })
        }
    }

    public func sshClient(for host: SSHHostID) async throws -> SSHClient {
        try await client(for: host)
    }

    private func withSFTP<T: Sendable>(
        _ host: SSHHostID, label: String, timeout: Duration = .seconds(60),
        _ body: @escaping @Sendable (SFTPClient) async throws -> T
    ) async throws -> T {
        try await withTimeout(timeout, command: label, host: host) { client in
            let sftp = try await client.openSFTP()
            do {
                let result = try await body(sftp)
                try? await sftp.close()
                return result
            } catch {
                try? await sftp.close()
                throw error
            }
        }
    }

    // MARK: - Connections

    private func client(for host: SSHHostID, patientJump: Bool = false) async throws -> SSHClient {
        if let live = clients[host], live.isConnected { return live }
        if let inFlight = connecting[host] { return try await inFlight.value }

        await dropJumpedChildren(of: host, inBackground: true)

        let attempts = patientJump ? 8 : 3
        let task = Task { try await self.openLink(to: host, maxAttempts: attempts) }
        connecting[host] = task
        defer { connecting[host] = nil }
        let client = try await task.value
        clients[host] = client
        startKeepalive(for: host, client: client)
        return client
    }

    private func openLink(to host: SSHHostID, maxAttempts: Int) async throws -> SSHClient {
        guard let route = route(to: host) else {
            throw ServerControlError.notConfigured("this deployment has no address for that machine")
        }
        guard let parent = route.parent else {
            directLinks.remove(host)
            do {
                let client = try await dial(to: route.address, as: host)
                fallbackLinks.remove(host)
                return client
            } catch let failure as DialFailure {
                guard let fallback = route.fallback, failure.machineDidNotAnswer
                else { throw failure.error }
                let client = try await connect(to: fallback, as: host)
                fallbackLinks.insert(host)
                return client
            }
        }

        var lastError: Error?
        for attempt in 1...maxAttempts {
            if attempt > 1 {
                try await Task.sleep(for: .seconds(4))
            }
            do {
                let jumped = try await client(for: parent).jump(to: sshSettings(for: route.address, as: host))
                directLinks.remove(host)
                return jumped
            } catch let error as ServerControlError {
                if case .connectionFailed = error, let direct = try? await connectDirectly(to: host, route: route) {
                    return direct
                }
                throw error // config/auth problems — retrying cannot help
            } catch {
                lastError = error
            }
        }
        // The tunnel never came back. Same last resort as above.
        if let direct = try? await connectDirectly(to: host, route: route) {
            return direct
        }
        throw ServerControlError.connectionFailed(
            "home server unreachable through the tunnel: \(String(describing: lastError ?? ServerControlError.notConfigured("no attempt made")))")
    }

    private func connectDirectly(to host: SSHHostID, route: Route) async throws -> SSHClient {
        guard let fallback = route.fallback else {
            throw ServerControlError.notConfigured("no local address for the home server")
        }
        let client = try await connect(to: fallback, as: host)
        directLinks.insert(host)
        return client
    }

    private struct DialFailure: Error {
        let error: ServerControlError
        let machineDidNotAnswer: Bool
    }

    private nonisolated func isDialFailure(_ error: Error) -> Bool {
        switch error {
        case is ServerControlError: return false    // ours, and already a decision
        case is NIOConnectionError: return true     // every address for the name failed
        case is SocketAddressError: return true     // the name does not resolve
        case is IOError: return true                // POSIX refused, unreachable, reset
        case let channel as ChannelError:
            switch channel {
            case .connectTimeout, .connectPending, .unknownLocalAddress, .operationUnsupported:
                return true
            default: return false
            }
        default: return false                       // authentication, host keys, SSH itself
        }
    }

    private func connect(to address: Route.Address, as host: SSHHostID) async throws -> SSHClient {
        do {
            return try await dial(to: address, as: host)
        } catch let failure as DialFailure {
            throw failure.error
        }
    }

    private func dial(to address: Route.Address, as host: SSHHostID) async throws -> SSHClient {
        do {
            if let hop = address.bastion {
                return try await bastionClient(hop).jump(to: sshSettings(for: address, as: host))
            }
            return try await SSHDial.connect(sshSettings(for: address, as: host), through: settings.proxy)
        } catch let error as ServerControlError {
            throw DialFailure(error: error, machineDidNotAnswer: false)
        } catch {
            throw DialFailure(error: .connectionFailed(String(describing: error)),
                              machineDidNotAnswer: isDialFailure(error))
        }
    }

    /// The session to a jump host, opened once and shared
    private func bastionClient(_ hop: SSHConnectionSettings.Hop) async throws -> SSHClient {
        if let live = bastions[hop.endpoint], live.isConnected { return live }
        bastions[hop.endpoint] = nil
        let onPin = onPinBastionHostKey
        let endpoint = hop.endpoint
        let username = hop.username
        let authenticationMethod: @Sendable () -> SSHAuthenticationMethod
        if let password = hop.password {
            authenticationMethod = { .passwordBased(username: username, password: password) }
        } else {
            let key: Curve25519.Signing.PrivateKey
            do {
                key = try Curve25519.Signing.PrivateKey(rawRepresentation: hop.privateKeySeed)
            } catch {
                throw ServerControlError.notConfigured("invalid SSH private key for the bastion")
            }
            authenticationMethod = { .ed25519(username: username, privateKey: key) }
        }
        let settings = SSHClientSettings(
            host: hop.host,
            port: hop.port,
            authenticationMethod: authenticationMethod,
            hostKeyValidator: .custom(
                TOFUHostKeyValidator(hostLabel: hop.host, pinnedKey: hop.pinnedHostKey) { presented in
                    onPin(endpoint, presented)
                })
        )
        do {
            let client = try await SSHDial.connect(settings, through: self.settings.proxy)
            bastions[hop.endpoint] = client
            return client
        } catch let error as ServerControlError {
            throw error
        } catch {
            throw ServerControlError.connectionFailed(
                "the bastion \(hop.host) could not be reached: \(String(describing: error))")
        }
    }

    public func isReachedByFallback(_ host: SSHHostID) -> Bool {
        fallbackLinks.contains(host)
    }

    private func sshSettings(for address: Route.Address, as host: SSHHostID) throws -> SSHClientSettings {
        try clientSettings(host: address.host, port: address.port, hostID: host, pinned: address.pin)
    }

    private func clientSettings(host: String, port: Int, hostID: SSHHostID,
                                pinned: String?) throws -> SSHClientSettings {
        let username = settings.username
        let onPin = onPinHostKey
        let authenticationMethod: @Sendable () -> SSHAuthenticationMethod
        if let password = settings.passwords[hostID] {
            authenticationMethod = { .passwordBased(username: username, password: password) }
        } else {
            let key: Curve25519.Signing.PrivateKey
            do {
                key = try Curve25519.Signing.PrivateKey(rawRepresentation: settings.privateKeySeed)
            } catch {
                throw ServerControlError.notConfigured("invalid SSH private key in Keychain")
            }
            authenticationMethod = { .ed25519(username: username, privateKey: key) }
        }
        return SSHClientSettings(
            host: host,
            port: port,
            authenticationMethod: authenticationMethod,
            hostKeyValidator: .custom(TOFUHostKeyValidator(hostLabel: host, pinnedKey: pinned) { presented in
                onPin(hostID, presented)
            })
        )
    }

    // MARK: - Helpers

    /// Races the operation against the deadline
    private func acquireChannel() async throws {
        guard activeChannels >= Self.maxConcurrentChannels else {
            activeChannels += 1
            return
        }
        let id = UUID()
        let acquired = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                // Cancelled before parking: resume straight away, nothing to unpark later.
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    channelWaiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelChannelWaiter(id) }
        }
        guard acquired else { throw CancellationError() }
    }

    /// Unparks a cancelled waiter
    private func cancelChannelWaiter(_ id: UUID) {
        guard let index = channelWaiters.firstIndex(where: { $0.id == id }) else { return }
        channelWaiters.remove(at: index).continuation.resume(returning: false)
    }

    private func releaseChannel() {
        if channelWaiters.isEmpty {
            activeChannels -= 1
        } else {
            channelWaiters.removeFirst().continuation.resume(returning: true)
        }
    }

    private func withTimeout<T: Sendable>(
        _ timeout: Duration, command: String, host: SSHHostID,
        _ body: @escaping @Sendable (SSHClient) async throws -> T
    ) async throws -> T {
        let client = try await client(for: host)
        try await acquireChannel()
        defer { releaseChannel() }
        return try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await body(client) }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let result = first else {
                group.cancelAll()
                if !(await Self.linkAnswers(client)) { await self.reset(host) }
                throw ServerControlError.timeout(command: command)
            }
            return result
        }
    }

    /// Whether the connection still answers a trivial command
    private static func linkAnswers(_ client: SSHClient) async -> Bool {
        guard client.isConnected else { return false }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                guard let stream = try? await client.executeCommandStream("true") else { return false }
                do { for try await _ in stream {} } catch is SSHClient.CommandFailed { return true } catch { return false }
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return false
            }
            let answered = await group.next() ?? false
            group.cancelAll()
            return answered
        }
    }

    /// Per-host teardown when the link stops answering
    private func reset(_ host: SSHHostID) async {
        await dropJumpedChildren(of: host, inBackground: false)
        await closeLink(host)
    }
}

/// One SSH stream, decoded at character boundaries
struct UTF8Carry {
    private var pending: [UInt8] = []

    mutating func append(_ buffer: ByteBuffer) -> String {
        pending.append(contentsOf: buffer.readableBytesView)
        let keep = Self.incompleteTail(pending)
        let ready = pending.dropLast(keep)
        pending = Array(pending.suffix(keep))
        return String(decoding: ready, as: UTF8.self)
    }

    /// What is left at the end, decoded as it is
    mutating func flush() -> String {
        defer { pending = [] }
        return String(decoding: pending, as: UTF8.self)
    }

    /// Trailing bytes of an unfinished character
    static func incompleteTail(_ bytes: [UInt8]) -> Int {
        var back = 0
        for byte in bytes.reversed().prefix(3) {
            back += 1
            if byte & 0b1100_0000 == 0b1000_0000 { continue }
            let needed = byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : byte >= 0xC0 ? 2 : 1
            return needed > back ? back : 0
        }
        return 0
    }
}

extension CitadelCommandRunner: RemoteFileBrowser {
    public func homeDirectory(on host: SSHHostID) async throws -> String {
        try await withSFTP(host, label: "sftp: home directory") { sftp in
            try await sftp.getRealPath(atPath: ".")
        }
    }

    public func listDirectory(_ path: String, on host: SSHHostID) async throws -> [RemoteFileEntry] {
        try await withSFTP(host, label: "sftp: list \(path)") { sftp in
            let listing = try await sftp.listDirectory(atPath: path)
            let entries = listing.flatMap(\.components).compactMap { component -> RemoteFileEntry? in
                let name = component.filename
                guard name != ".", name != ".." else { return nil }
                return RemoteFileEntry(
                    name: name,
                    path: RemotePath.join(path, name),
                    kind: RemoteFileEntry.kind(fromPermissions: component.attributes.permissions),
                    size: component.attributes.size,
                    modified: component.attributes.accessModificationTime?.modificationTime
                )
            }
            return RemoteFileEntry.sorted(entries)
        }
    }

    public func downloadFile(_ path: String, on host: SSHHostID, maxBytes: UInt64) async throws -> Data {
        try await withSFTP(host, label: "sftp: download \(path)", timeout: .seconds(600)) { sftp in
            let file = try await sftp.openFile(filePath: path, flags: .read)
            do {
                let attributes = try await file.readAttributes()
                if let size = attributes.size, size > maxBytes {
                    throw ServerControlError.fileTooLarge(path: path, size: size, limit: maxBytes)
                }
                let buffer = try await file.readAll()
                try await file.close()
                return Data(buffer: buffer)
            } catch {
                try? await file.close()
                throw error
            }
        }
    }

    public func uploadFile(_ data: Data, to path: String, on host: SSHHostID) async throws {
        try await withSFTP(host, label: "sftp: upload \(path)", timeout: .seconds(600)) { sftp in
            let file = try await sftp.openFile(filePath: path,
                                               flags: [.write, .create, .truncate])
            do {
                try await file.write(ByteBuffer(data: data))
                try await file.close()
            } catch {
                try? await file.close()
                throw error
            }
        }
    }

    public func deleteFile(_ entry: RemoteFileEntry, on host: SSHHostID) async throws {
        try await withSFTP(host, label: "sftp: delete \(entry.path)") { sftp in
            if entry.kind == .directory {
                try await sftp.rmdir(at: entry.path)
            } else {
                try await sftp.remove(at: entry.path)
            }
        }
    }
}
