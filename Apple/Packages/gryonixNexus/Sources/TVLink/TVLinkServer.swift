import Foundation
import Network
import os

/// What the TV app decides; the server only carries frames
public protocol TVLinkHost: AnyObject, Sendable {
    func pairingCode(for phone: TVPeer) async -> TVPairingCode
    /// A pairing ended; `codeTried` once the phone sent a code
    func pairingEnded(phone: TVPeer, result: TVPairingResult?, codeTried: Bool) async
    func pairingKey(for phoneID: String) async -> Data?
    func handle(_ request: TVMessage, from phoneID: String) async -> TVMessage
}

/// The TV's listener: advertised over Bonjour, one handler per connection
public final class TVLinkServer: @unchecked Sendable {
    public static let preferredPort: UInt16 = 47_390
    public static let codeEntryTimeout: TimeInterval = 180

    private let tv: TVPeer
    private weak var host: TVLinkHost?
    private let advertise: Bool
    private let random: TVLinkRandom
    private let queue = DispatchQueue(label: "com.skaymer.gryonixnexus.tvlink.server")
    private let lock = NSLock()
    private var listener: NWListener?
    private var beacon: DispatchSourceTimer?
    private var pairing = false
    private var portContinuation: OnceContinuation<UInt16>?

    private static let log = Logger(subsystem: "com.skaymer.gryonixnexus", category: "tvlink")

    public init(tv: TVPeer, host: TVLinkHost, advertise: Bool = true,
                random: TVLinkRandom = SystemTVLinkRandom()) {
        self.tv = tv
        self.host = host
        self.advertise = advertise
        self.random = random
    }

    /// Starts listening; returns the port it got
    @discardableResult
    public func start(port: UInt16? = TVLinkServer.preferredPort) async throws -> UInt16 {
        do {
            return try await listen(on: port.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any)
        } catch where port != nil {
            return try await listen(on: .any)
        }
    }

    public func stop() {
        lock.withLock {
            beacon?.cancel()
            beacon = nil
            listener?.cancel()
            listener = nil
        }
    }

    /// The Bonjour record, stamped with the time
    public static func advertisement(for tv: TVPeer, now: Date = Date()) -> NWListener.Service {
        let record = NWTXTRecord([TVLinkService.idKey: tv.id,
                                  TVLinkService.awakeKey: String(Int(now.timeIntervalSince1970))])
        return NWListener.Service(name: tv.name, type: TVLinkService.type, domain: nil, txtRecord: record)
    }

    private func keepAdvertising(_ listener: NWListener) {
        guard advertise else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = DispatchTimeInterval.seconds(Int(TVLinkService.awakeInterval))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [tv] in listener.service = Self.advertisement(for: tv) }
        timer.resume()
        beacon?.cancel()
        beacon = timer
    }

    private func listen(on port: NWEndpoint.Port) async throws -> UInt16 {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: port)
        if advertise { listener.service = Self.advertisement(for: tv) }
        let ready = OnceContinuation<UInt16>()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.resume(.success(listener.port?.rawValue ?? 0))
            case .failed(let error):
                Self.log.error("listener failed: \(String(describing: error), privacy: .public)")
                ready.resume(.failure(TVLinkError.connectionFailed(error.localizedDescription)))
                listener.cancel()
            case .cancelled:
                ready.resume(.failure(TVLinkError.closed))
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            Task { await self.serve(TVLinkConnection(connection)) }
        }
        listener.start(queue: queue)
        let port = try await ready.value()
        lock.withLock {
            self.listener?.cancel()
            self.listener = listener
            keepAdvertising(listener)
        }
        return port
    }

    private func serve(_ connection: TVLinkConnection) async {
        await connection.accept()
        defer { Task { await connection.close() } }
        do {
            let hello = try await connection.receiveHandshake()
            switch hello.mode {
            case .pair: try await pair(hello, on: connection)
            case .session: try await session(hello, on: connection)
            case nil: try? await connection.send(.refusal(.protocolError))
            }
        } catch {
            Self.log.notice("connection ended: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Pairing

    private func pair(_ hello: TVHandshakeMessage, on connection: TVLinkConnection) async throws {
        guard let host else { return }
        guard hello.v == TVLinkService.protocolVersion else {
            try await connection.send(.refusal(.version))
            return
        }
        let claimed = lock.withLock { () -> Bool in
            if pairing { return false }
            pairing = true
            return true
        }
        guard claimed else {
            try await connection.send(.refusal(.busy))
            return
        }
        defer { lock.withLock { pairing = false } }

        let phone = TVPeer(id: hello.id ?? "", name: hello.name ?? "")
        let code = await host.pairingCode(for: phone)
        var machine = TVPairingTV(tv: tv, code: code, random: random)
        var result: TVPairingResult?
        var codeTried = false
        defer {
            Task { [result, codeTried] in await host.pairingEnded(phone: phone, result: result, codeTried: codeTried) }
        }
        do {
            try await connection.send(machine.receive(hello))
            var timeout = Self.codeEntryTimeout
            while !machine.awaitsSealedConfirmation {
                let message = try await connection.receiveHandshake(timeout: timeout)
                codeTried = true
                timeout = 20
                try await connection.send(machine.receive(message))
            }
            let step = try machine.receiveSealed(await connection.receive())
            if case .finished(let sealed, let paired) = step {
                try await connection.send(sealed)
                result = paired
            }
        } catch TVHandshakeError.codeMismatch {
            try? await connection.send(.refusal(.wrongCode))
        } catch TVHandshakeError.refused(let reason) {
            try? await connection.send(.refusal(reason))
        } catch TVHandshakeError.unexpected {
            try? await connection.send(.refusal(.protocolError))
        }
    }

    // MARK: - Sessions

    private func session(_ hello: TVHandshakeMessage, on connection: TVLinkConnection) async throws {
        guard let host else { return }
        let key = await host.pairingKey(for: hello.id ?? "")
        let accepted: TVSessionTV.Accepted
        do {
            accepted = try TVSessionTV(tv: tv, random: random).accept(hello) { _ in key }
        } catch TVHandshakeError.refused(let reason) {
            try await connection.send(.refusal(reason))
            return
        } catch {
            try await connection.send(.refusal(.protocolError))
            return
        }
        try await connection.send(accepted.reply)
        var channel = accepted.channel
        while true {
            let request: TVMessage
            do {
                request = try channel.openMessage(await connection.receive(timeout: 30))
            } catch TVLinkError.closed {
                return
            }
            let answer = await host.handle(request, from: accepted.phoneID)
            try await connection.send(channel.seal(answer))
            if request.t == .unpair { return }
        }
    }
}
