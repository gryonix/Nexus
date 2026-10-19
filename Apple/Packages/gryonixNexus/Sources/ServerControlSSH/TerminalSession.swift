import Citadel
import Crypto
import Foundation
import NIOCore
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

    public init(host: String, port: Int, pinnedHostKey: String?, parent: Hop? = nil) {
        self.host = host
        self.port = port
        self.pinnedHostKey = pinnedHostKey
        self.parent = parent
    }
}

/// What a live terminal says
public enum TerminalEvent: Sendable {
    case output(Data)
    /// The session ended
    case closed(reason: String?)
}

@available(macOS 15.0, *)
public actor TerminalSession {
    private let endpoint: TerminalEndpoint
    private let login: TerminalLogin
    private let onPinHostKey: @Sendable (String, String) -> Void

    private var client: SSHClient?
    private var bastion: SSHClient?
    private var writer: TTYStdinWriter?
    private var pump: Task<Void, Never>?
    private var continuation: AsyncStream<TerminalEvent>.Continuation?
    private var isOpen = false

    public init(endpoint: TerminalEndpoint,
                login: TerminalLogin,
                onPinHostKey: @escaping @Sendable (String, String) -> Void) {
        self.endpoint = endpoint
        self.login = login
        self.onPinHostKey = onPinHostKey
    }

    /// Connect, ask for a pseudo-terminal, and start pumping its output
    public func start(columns: Int, rows: Int) async throws -> AsyncStream<TerminalEvent> {
        guard client == nil else {
            throw ServerControlError.notConfigured("this terminal is already open")
        }
        let client = try await connect()
        self.client = client

        let (stream, continuation) = AsyncStream<TerminalEvent>.makeStream()
        self.continuation = continuation
        isOpen = true

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
        return stream
    }

    public func send(_ data: Data) async {
        guard isOpen, let writer else { return }
        try? await writer.write(ByteBuffer(bytes: data))
    }

    /// Tell the far end the window changed
    public func resize(columns: Int, rows: Int) async {
        guard isOpen, let writer else { return }
        try? await writer.changeSize(cols: columns, rows: rows,
                                     pixelWidth: 0, pixelHeight: 0)
    }

    /// Hang up
    public func close() async {
        isOpen = false
        pump?.cancel()
        pump = nil
        writer = nil
        let client = self.client
        let bastion = self.bastion
        self.client = nil
        self.bastion = nil
        continuation?.finish()
        continuation = nil
        try? await client?.close()
        try? await bastion?.close()
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

    private func adopt(writer: TTYStdinWriter) {
        self.writer = writer
    }

    private func emit(_ event: TerminalEvent) {
        continuation?.yield(event)
    }

    private func finish(reason: String?) {
        guard isOpen else { return }
        isOpen = false
        writer = nil
        continuation?.yield(.closed(reason: reason))
        continuation?.finish()
        continuation = nil
    }

    private func connect() async throws -> SSHClient {
        let settings = try clientSettings(host: endpoint.host, port: endpoint.port,
                                          pinned: endpoint.pinnedHostKey, login: login)
        do {
            guard let hop = endpoint.parent else {
                return try await SSHDial.connect(settings)
            }
            let through = try await SSHDial.connect(clientSettings(
                host: hop.host, port: hop.port, pinned: hop.pinnedHostKey, login: hop.login))
            do {
                let target = try await through.jump(to: settings)
                bastion = through
                return target
            } catch {
                try? await through.close()
                throw error
            }
        } catch let error as ServerControlError {
            throw error
        } catch {
            throw ServerControlError.connectionFailed(String(describing: error))
        }
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
