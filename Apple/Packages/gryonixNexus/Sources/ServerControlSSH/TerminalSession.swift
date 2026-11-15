import Citadel
import Crypto
import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import ServerControl

/// Who to sign in as
public struct TerminalLogin: Sendable, Hashable {
    public enum Secret: Sendable, Hashable {
        case password(String)
        case privateKeySeed(Data)
    }

    public var username: String
    public var secret: Secret

    public init(username: String, secret: Secret) {
        self.username = username
        self.secret = secret
    }
}

extension TerminalLogin {
    public static func seed(fromOpenSSHKey text: String) throws -> Data {
        do {
            return try Curve25519.Signing.PrivateKey(sshEd25519: text).rawRepresentation
        } catch {
            throw ServerControlError.notConfigured(
                "this does not look like an unencrypted OpenSSH ed25519 private key")
        }
    }
}

public struct TerminalEndpoint: Sendable {
    public var host: String
    public var port: Int
    public var pinnedHostKey: String?
    public var parent: Hop?
    /// Machines dialled before `parent`, outermost first
    public var outer: [Hop]
    /// Which way this route goes, for the screen
    public var kind: Kind
    /// Gives up sooner on routes that may not exist here
    public var connectTimeout: Duration
    public var proxy: ProxyConnect.Endpoint?

    public enum Kind: String, Sendable, Hashable {
        case direct
        case localNetwork
        case relay
        case tunnelAddress
        case fallbackAddress
    }

    /// The machine in front of this one
    public struct Hop: Sendable {
        public var host: String
        public var port: Int
        public var pinnedHostKey: String?
        public var login: TerminalLogin

        public init(host: String, port: Int, pinnedHostKey: String?, login: TerminalLogin) {
            self.host = host
            self.port = port
            self.pinnedHostKey = pinnedHostKey
            self.login = login
        }
    }

    public init(host: String, port: Int, pinnedHostKey: String?, parent: Hop? = nil,
                outer: [Hop] = [],
                kind: Kind = .direct, connectTimeout: Duration = .seconds(30),
                proxy: ProxyConnect.Endpoint? = nil) {
        self.host = host
        self.port = port
        self.pinnedHostKey = pinnedHostKey
        self.parent = parent
        self.outer = outer
        self.kind = kind
        self.connectTimeout = connectTimeout
        self.proxy = proxy
    }

    /// One line naming where the shell goes
    public var summary: String {
        (hops.map { "\($0.host):\($0.port)" } + ["\(host):\(port)"]).joined(separator: " → ")
    }

    /// Every machine before this one, outermost first
    public var hops: [Hop] { outer + (parent.map { [$0] } ?? []) }
}

/// What a live terminal says
public enum TerminalEvent: Sendable {
    case output(Data)
    /// The session ended
    case closed(reason: String?)
}

/// Every route failed; each attempt and why
public struct TerminalRoutesFailed: Error, Sendable, CustomStringConvertible {
    public let attempts: [(route: TerminalEndpoint, reason: String)]

    public init(attempts: [(route: TerminalEndpoint, reason: String)]) {
        self.attempts = attempts
    }

    public var description: String {
        attempts.map { "\($0.route.summary): \($0.reason)" }.joined(separator: "\n")
    }
}

@available(macOS 15.0, *)
public actor TerminalSession {
    /// Quiet this long, the session sends a keepalive
    public static let keepaliveInterval = Duration.seconds(15)

    private let routes: [TerminalEndpoint]
    private let login: TerminalLogin
    private let onPinHostKey: @Sendable (String, String) -> Void

    private var client: SSHClient?
    private var bastion: SSHClient?
    private var writer: TTYStdinWriter?
    private var pump: Task<Void, Never>?
    private var keepalive: Task<Void, Never>?
    private var continuation: AsyncStream<TerminalEvent>.Continuation?
    private var isOpen = false
    private var size = (columns: 80, rows: 24)
    private var lastTraffic = ContinuousClock.now

    /// The route the live session went through
    public private(set) var connectedRoute: TerminalEndpoint?

    public init(endpoint: TerminalEndpoint,
                login: TerminalLogin,
                onPinHostKey: @escaping @Sendable (String, String) -> Void) {
        self.init(routes: [endpoint], login: login, onPinHostKey: onPinHostKey)
    }

    /// Routes are tried in order until one signs in
    public init(routes: [TerminalEndpoint],
                login: TerminalLogin,
                onPinHostKey: @escaping @Sendable (String, String) -> Void) {
        self.routes = routes
        self.login = login
        self.onPinHostKey = onPinHostKey
    }

    /// Connect, ask for a pseudo-terminal, and start pumping its output
    public func start(columns: Int, rows: Int) async throws -> AsyncStream<TerminalEvent> {
        guard client == nil else {
            throw ServerControlError.notConfigured("this terminal is already open")
        }
        let client = try await connectFirstWorkingRoute()
        self.client = client
        size = (columns, rows)

        let (stream, continuation) = AsyncStream<TerminalEvent>.makeStream()
        self.continuation = continuation
        isOpen = true
        lastTraffic = .now

        let request = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: columns,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )

        pump = Task { [weak self] in
            await self?.run(client: client, request: request)
        }
        keepalive = Task { [weak self] in
            await self?.keepAlive()
        }
        return stream
    }

    public func send(_ data: Data) async {
        guard isOpen, let writer else { return }
        lastTraffic = .now
        try? await writer.write(ByteBuffer(bytes: data))
    }

    /// Tell the far end the window changed
    public func resize(columns: Int, rows: Int) async {
        size = (columns, rows)
        guard isOpen, let writer else { return }
        lastTraffic = .now
        try? await writer.changeSize(cols: columns, rows: rows,
                                     pixelWidth: 0, pixelHeight: 0)
    }

    /// Hang up, outermost connection first
    public func close() async {
        isOpen = false
        writer = nil
        keepalive?.cancel()
        keepalive = nil
        let client = self.client
        let bastion = self.bastion
        self.client = nil
        self.bastion = nil
        continuation?.finish()
        continuation = nil
        // Closing the socket first leaves no channel half closed.
        try? await (bastion ?? client)?.close()
        if bastion != nil { try? await client?.close() }
        pump?.cancel()
        pump = nil
    }

    // MARK: - Private

    private func run(client: SSHClient,
                     request: SSHChannelRequestEvent.PseudoTerminalRequest) async {
        do {
            try await client.withPTY(request) { [weak self] inbound, outbound in
                await self?.adopt(writer: outbound)
                for try await chunk in inbound {
                    switch chunk {
                    case .stdout(let buffer), .stderr(let buffer):
                        await self?.emit(.output(Data(buffer.readableBytesView)))
                    }
                }
            }
            finish(reason: nil)
        } catch is CancellationError {
        } catch {
            finish(reason: String(describing: error))
        }
    }

    /// Resends the window size while nothing else flows
    private func keepAlive() async {
        let interval = Self.keepaliveInterval
        while !Task.isCancelled {
            let due = lastTraffic.advanced(by: interval)
            try? await Task.sleep(until: due, clock: .continuous)
            guard !Task.isCancelled, isOpen else { return }
            guard ContinuousClock.now >= lastTraffic.advanced(by: interval) else { continue }
            lastTraffic = .now
            guard let writer else { continue }
            // An unchanged size reaches no program on the server.
            try? await writer.changeSize(cols: size.columns, rows: size.rows,
                                         pixelWidth: 0, pixelHeight: 0)
        }
    }

    private func adopt(writer: TTYStdinWriter) {
        self.writer = writer
    }

    private func emit(_ event: TerminalEvent) {
        lastTraffic = .now
        continuation?.yield(event)
    }

    private func finish(reason: String?) {
        guard isOpen else { return }
        isOpen = false
        writer = nil
        keepalive?.cancel()
        keepalive = nil
        continuation?.yield(.closed(reason: reason))
        continuation?.finish()
        continuation = nil
    }

    private func connectFirstWorkingRoute() async throws -> SSHClient {
        var attempts: [(route: TerminalEndpoint, reason: String)] = []
        for (index, route) in routes.enumerated() {
            try Task.checkCancellation()
            do {
                let isLast = index == routes.count - 1
                let client = try await connect(route, pauses: isLast ? SSHDial.redialPauses : [])
                connectedRoute = route
                return client
            } catch {
                guard Self.mayTryAnotherRoute(after: error) else { throw error }
                attempts.append((route, Self.reason(error)))
            }
        }
        guard attempts.count > 1 else {
            throw ServerControlError.connectionFailed(attempts.first?.reason ?? "no route to this server")
        }
        throw TerminalRoutesFailed(attempts: attempts)
    }

    /// Wrong keys and passwords fail the same on every route
    static func mayTryAnotherRoute(after error: Error) -> Bool {
        switch error {
        case let failure as ServerControlError:
            if case .connectionFailed = failure { return true }
            if case .timeout = failure { return true }
            return false
        case is NIOConnectionError, is SocketAddressError, is IOError:
            return true
        case let channel as ChannelError:
            switch channel {
            case .connectTimeout, .connectPending, .unknownLocalAddress, .operationUnsupported,
                 .ioOnClosedChannel, .alreadyClosed, .eof:
                return true
            default:
                return false
            }
        case let citadel as CitadelError:
            return citadel == .channelCreationFailed || citadel == .channelFailure
        case let ssh as NIOSSHError:
            return ssh.type == .channelSetupRejected || ssh.type == .tcpShutdown
        default:
            return false
        }
    }

    private static func reason(_ error: Error) -> String {
        if case .connectionFailed(let text) = error as? ServerControlError { return text }
        if let error = error as? ServerControlError { return error.localizedDescription }
        return String(describing: error)
    }

    private func connect(_ route: TerminalEndpoint, pauses: [Duration]) async throws -> SSHClient {
        var settings = try clientSettings(host: route.host, port: route.port,
                                          pinned: route.pinnedHostKey, login: login)
        settings.connectTimeout = Self.timeAmount(route.connectTimeout)
        do {
            guard let first = route.hops.first else {
                return try await SSHDial.connect(settings, through: route.proxy, pauses: pauses)
            }
            var entry = try hopSettings(first)
            entry.connectTimeout = settings.connectTimeout
            let outermost = try await SSHDial.connect(entry, through: route.proxy, pauses: pauses)
            do {
                var through = outermost
                for hop in route.hops.dropFirst() {
                    through = try await through.jump(to: try self.hopSettings(hop))
                }
                let target = try await through.jump(to: settings)
                bastion = outermost
                return target
            } catch {
                try? await outermost.close()
                throw error
            }
        } catch let error as ServerControlError {
            throw error
        } catch {
            guard Self.mayTryAnotherRoute(after: error) else { throw error }
            throw ServerControlError.connectionFailed(String(describing: error))
        }
    }

    private func hopSettings(_ hop: TerminalEndpoint.Hop) throws -> SSHClientSettings {
        try clientSettings(host: hop.host, port: hop.port, pinned: hop.pinnedHostKey, login: hop.login)
    }

    private static func timeAmount(_ duration: Duration) -> TimeAmount {
        let (seconds, attoseconds) = duration.components
        return .nanoseconds(seconds * 1_000_000_000 + attoseconds / 1_000_000_000)
    }

    private func clientSettings(host: String, port: Int, pinned: String?,
                                login: TerminalLogin) throws -> SSHClientSettings {
        let username = login.username
        let authentication: @Sendable () -> SSHAuthenticationMethod
        switch login.secret {
        case .password(let password):
            authentication = { .passwordBased(username: username, password: password) }
        case .privateKeySeed(let seed):
            let key: Curve25519.Signing.PrivateKey
            do {
                key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
            } catch {
                throw ServerControlError.notConfigured("invalid private key for this login")
            }
            authentication = { .ed25519(username: username, privateKey: key) }
        }
        let onPin = onPinHostKey
        return SSHClientSettings(
            host: host,
            port: port,
            authenticationMethod: authentication,
            hostKeyValidator: .custom(TOFUHostKeyValidator(hostLabel: host,
                                                           pinnedKey: pinned,
                                                           onPin: { key in onPin(host, key) }))
        )
    }
}
