import Foundation
import Network

/// Where a phone last reached a TV
public struct TVAddress: Codable, Equatable, Hashable, Sendable {
    public var host: String
    public var port: UInt16

    public init(host: String, port: UInt16 = TVLinkServer.preferredPort) {
        self.host = host
        self.port = port
    }

    public init?(typed text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") {
            let host = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            let rest = trimmed[trimmed.index(after: close)...]
            if rest.isEmpty { self.init(host: host); return }
            guard rest.hasPrefix(":"), let port = UInt16(rest.dropFirst()), port > 0 else { return nil }
            self.init(host: host, port: port)
            return
        }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            self.init(host: trimmed)
        case 2:
            guard !parts[0].isEmpty, let port = UInt16(parts[1]), port > 0 else { return nil }
            self.init(host: String(parts[0]), port: port)
        default:
            self.init(host: trimmed)
        }
    }

    public var endpoint: NWEndpoint {
        .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? .any)
    }
}

public struct TVPairingLink: Equatable, Sendable {
    public var address: TVAddress
    public var code: TVPairingCode
    public var name: String?

    public init(address: TVAddress, code: TVPairingCode, name: String?) {
        self.address = address
        self.code = code
        self.name = name
    }

    /// `gryonixnexus://tv?host=…&port=…&code=…&name=…`
    public var url: URL? {
        var components = URLComponents()
        components.scheme = TVLinkService.linkScheme
        components.host = TVLinkService.linkHost
        components.queryItems = [
            URLQueryItem(name: "host", value: address.host),
            URLQueryItem(name: "port", value: String(address.port)),
            URLQueryItem(name: "code", value: code.digits),
        ] + (name.map { [URLQueryItem(name: "name", value: $0)] } ?? [])
        return components.url
    }

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == TVLinkService.linkScheme, components.host == TVLinkService.linkHost
        else { return nil }
        let items = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                               uniquingKeysWith: { first, _ in first })
        guard let host = items["host"], !host.isEmpty, let codeText = items["code"],
              let code = TVPairingCode(codeText) else { return nil }
        let port = items["port"].flatMap(UInt16.init) ?? TVLinkServer.preferredPort
        self.init(address: TVAddress(host: host, port: port), code: code, name: items["name"])
    }
}

public actor TVPairingAttempt {
    private let connection: TVLinkConnection
    private var machine: TVPairingPhone
    public let tv: TVPeer
    /// The address the connection reached, to come back to later
    public let address: TVAddress?

    public static func start(_ endpoint: NWEndpoint, phone: TVPeer,
                             random: TVLinkRandom = SystemTVLinkRandom()) async throws -> TVPairingAttempt {
        let connection = TVLinkConnection(endpoint: endpoint)
        try await connection.open()
        var machine = TVPairingPhone(phone: phone, random: random)
        do {
            try await connection.send(machine.hello())
            guard case .needsCode = try machine.receive(await connection.receiveHandshake()),
                  let tv = machine.tvPeer else { throw TVHandshakeError.unexpected }
            let reached = await connection.remoteHostPort.map { TVAddress(host: $0.host, port: $0.port) }
            return TVPairingAttempt(connection: connection, machine: machine, tv: tv, address: reached)
        } catch {
            await connection.close()
            throw error
        }
    }

    private init(connection: TVLinkConnection, machine: TVPairingPhone, tv: TVPeer, address: TVAddress?) {
        self.connection = connection
        self.machine = machine
        self.tv = tv
        self.address = address
    }

    /// Runs the twenty rounds with the code the person typed
    public func enter(_ code: TVPairingCode) async throws -> TVPairingResult {
        defer { Task { await connection.close() } }
        var outgoing = try machine.enter(code)
        while true {
            try await connection.send(outgoing)
            switch try machine.receive(await connection.receiveHandshake()) {
            case .send(let next):
                outgoing = next
            case .sendSealed(let sealed):
                try await connection.send(sealed)
                return try machine.receiveSealed(await connection.receive())
            case .needsCode:
                throw TVHandshakeError.unexpected
            }
        }
    }

    public func cancel() async {
        await connection.close()
    }
}

/// One session with a paired TV: requests in, answers out
public enum TVLinkClient {
    public static func exchange(_ requests: [TVMessage], at endpoint: NWEndpoint, phone: TVPeer,
                                tvID: String, pairingKey: Data,
                                random: TVLinkRandom = SystemTVLinkRandom()) async throws -> [TVMessage] {
        let connection = TVLinkConnection(endpoint: endpoint)
        try await connection.open()
        defer { Task { await connection.close() } }
        let handshake = TVSessionPhone(phone: phone, tvID: tvID, pairingKey: pairingKey, random: random)
        try await connection.send(handshake.hello())
        var channel = try handshake.receive(await connection.receiveHandshake())
        var answers: [TVMessage] = []
        for request in requests {
            try await connection.send(channel.seal(request))
            answers.append(try channel.openMessage(await connection.receive()))
        }
        return answers
    }
}
