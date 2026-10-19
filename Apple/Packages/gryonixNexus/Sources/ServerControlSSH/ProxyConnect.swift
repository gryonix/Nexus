import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import ServerControl

public enum ProxyConnect {
    /// One proxy, as the transport needs it
    public struct Endpoint: Sendable, Hashable {
        public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
            case socks5
            case httpConnect
        }

        public let kind: Kind
        public let host: String
        public let port: Int
        public let username: String?
        public let password: String?

        public init(kind: Kind, host: String, port: Int,
                    username: String? = nil, password: String? = nil) {
            self.kind = kind
            self.host = host
            self.port = port
            self.username = username
            self.password = password
        }
    }

    /// The server end of a session, opened by the app
    public struct Link: Sendable {
        public let channel: Channel
        let heard: NIOLockedValueBox<Bool>

        /// Whether the server sent any byte at all
        public var serverSpoke: Bool { heard.withLockedValue { $0 } }
    }

    /// Opens the server end, directly or through a proxy
    public static func link(to host: String, port: Int, through proxy: Endpoint?,
                            group: EventLoopGroup, timeout: TimeAmount) async throws -> Link {
        let heard = NIOLockedValueBox(false)
        let channel: Channel
        if let proxy {
            channel = try await connect(through: proxy, to: host, port: port, group: group, heard: heard)
        } else {
            channel = try await ClientBootstrap(group: group)
                .connectTimeout(timeout)
                .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
                .channelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        try holdReads(on: channel, noting: heard)
                    }
                }
                .connect(host: host, port: port)
                .get()
        }
        return Link(channel: channel, heard: heard)
    }

    /// Notes the server's first byte and holds reads until glued
    private static func holdReads(on channel: Channel, noting heard: NIOLockedValueBox<Bool>) throws {
        try channel.pipeline.syncOperations.addHandler(HeardHandler(heard: heard))
        try channel.pipeline.syncOperations.addHandler(PendingReadHandler(), name: pendingName)
    }

    /// A loopback door SSH dials, glued to `link`
    public static func door(to link: Link, group: EventLoopGroup) async throws -> Door {
        let accepted = NIOLockedValueBox(false)
        let outbound = link.channel
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .childChannelInitializer { inbound in
                let first = accepted.withLockedValue { value -> Bool in
                    if value { return false }
                    value = true
                    return true
                }
                guard first else { return inbound.close() }
                return glue(inbound, outbound).flatMapError { error in
                    _ = outbound.close()
                    _ = inbound.close()
                    return inbound.eventLoop.makeFailedFuture(error)
                }
            }
        let listener = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        guard let localPort = listener.localAddress?.port else {
            try? await listener.close()
            throw ServerControlError.connectionFailed("could not open a local door for SSH")
        }
        return Door(port: localPort, listener: listener, link: link)
    }

    private static let pendingName = "gnx-pending-read"

    /// Joins the door to the server end, releasing held reads
    private static func glue(_ inbound: Channel, _ outbound: Channel) -> EventLoopFuture<Void> {
        inbound.pipeline.addHandler(RelayHandler(peer: outbound)).flatMap {
            outbound.pipeline.addHandler(RelayHandler(peer: inbound))
        }.flatMap {
            outbound.pipeline.removeHandler(name: pendingName)
        }
    }

    private final class HeardHandler: ChannelInboundHandler {
        typealias InboundIn = ByteBuffer
        private let heard: NIOLockedValueBox<Bool>

        init(heard: NIOLockedValueBox<Bool>) { self.heard = heard }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            heard.withLockedValue { $0 = true }
            context.fireChannelRead(data)
        }
    }

    private final class PendingReadHandler: ChannelInboundHandler, RemovableChannelHandler {
        typealias InboundIn = ByteBuffer
        private var held: [NIOAny] = []

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            held.append(data)
        }

        func handlerRemoved(context: ChannelHandlerContext) {
            for data in held { context.fireChannelRead(data) }
            if !held.isEmpty { context.fireChannelReadComplete() }
            held = []
        }
    }

    /// One direction of the pipe
    private final class RelayHandler: ChannelInboundHandler {
        typealias InboundIn = ByteBuffer
        typealias OutboundOut = ByteBuffer

        private let peer: Channel

        init(peer: Channel) { self.peer = peer }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let buffer = unwrapInboundIn(data)
            peer.writeAndFlush(buffer).whenFailure { [weak peer] _ in
                peer?.close(promise: nil)
                context.close(promise: nil)
            }
        }

        func channelWritabilityChanged(context: ChannelHandlerContext) {
            peer.setOption(ChannelOptions.autoRead, value: context.channel.isWritable)
                .whenFailure { _ in }
        }

        func channelInactive(context: ChannelHandlerContext) {
            peer.close(promise: nil)
            context.fireChannelInactive()
        }

        func errorCaught(context: ChannelHandlerContext, error: Error) {
            peer.close(promise: nil)
            context.close(promise: nil)
        }
    }

    /// A door, the listener behind it and the server end
    public struct Door: Sendable {
        /// The loopback port SSH dials
        public let port: Int
        private let listener: Channel
        private let link: Link

        init(port: Int, listener: Channel, link: Link) {
            self.port = port
            self.listener = listener
            self.link = link
        }

        public var serverSpoke: Bool { link.serverSpoke }

        /// Stops accepting; a glued session lives on
        public func close() async {
            try? await listener.close()
        }

        /// Closes the listener and the server end
        public func abort() async {
            try? await listener.close()
            try? await link.channel.close()
        }
    }

    private static func connect(through endpoint: Endpoint,
                                to host: String, port: Int,
                                group: EventLoopGroup,
                                heard: NIOLockedValueBox<Bool>) async throws -> Channel {
        let handshake = ProxyHandshakeHandler(endpoint: endpoint, targetHost: host, targetPort: port)
        let channel: Channel
        do {
            channel = try await ClientBootstrap(group: group)
                .connectTimeout(.seconds(20))
                .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
                .channelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.addHandler(handshake)
                        try holdReads(on: channel, noting: heard)
                    }
                }
                .connect(host: endpoint.host, port: endpoint.port)
                .get()
        } catch {
            throw ServerControlError.connectionFailed(
                "the proxy \(endpoint.host):\(endpoint.port) could not be reached: \(error)")
        }
        do {
            try await handshake.completion.get()
        } catch {
            try? await channel.close()
            throw error
        }
        try? await channel.pipeline.removeHandler(handshake).get()
        return channel
    }
}

/// The negotiation itself
final class ProxyHandshakeHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private enum Step {
        case greeting
        case authenticating
        case connecting
        case httpReply
        case done
    }

    private let endpoint: ProxyConnect.Endpoint
    private let targetHost: String
    private let targetPort: Int
    private var step: Step = .greeting
    private var buffer = ByteBuffer()
    private var promise: EventLoopPromise<Void>?
    private var deadline: Scheduled<Void>?

    private static let handshakeSeconds: Int64 = 20

    private(set) var completion: EventLoopFuture<Void>!

    init(endpoint: ProxyConnect.Endpoint, targetHost: String, targetPort: Int) {
        self.endpoint = endpoint
        self.targetHost = targetHost
        self.targetPort = targetPort
    }

    func handlerAdded(context: ChannelHandlerContext) {
        let promise = context.eventLoop.makePromise(of: Void.self)
        self.promise = promise
        completion = promise.futureResult
    }

    func channelActive(context: ChannelHandlerContext) {
        deadline = context.eventLoop.scheduleTask(in: .seconds(Self.handshakeSeconds)) { [weak self] in
            guard let self, self.step != .done else { return }
            self.fail(ServerControlError.connectionFailed("the proxy did not answer"), context: context)
        }
        switch endpoint.kind {
        case .socks5:
            // Greeting: version 5, the methods we can actually perform.
            var out = context.channel.allocator.buffer(capacity: 4)
            out.writeInteger(UInt8(5))
            if endpoint.username?.isEmpty == false {
                out.writeInteger(UInt8(2))
                out.writeInteger(UInt8(0))    // no authentication
                out.writeInteger(UInt8(2))    // username/password
            } else {
                out.writeInteger(UInt8(1))
                out.writeInteger(UInt8(0))
            }
            context.writeAndFlush(wrapOutboundOut(out), promise: nil)
        case .httpConnect:
            step = .httpReply
            var request = "CONNECT \(targetHost):\(targetPort) HTTP/1.1\r\n"
            request += "Host: \(targetHost):\(targetPort)\r\n"
            if let user = endpoint.username, !user.isEmpty {
                let pair = "\(user):\(endpoint.password ?? "")"
                let encoded = Data(pair.utf8).base64EncodedString()
                request += "Proxy-Authorization: Basic \(encoded)\r\n"
            }
            request += "Proxy-Connection: keep-alive\r\n\r\n"
            var out = context.channel.allocator.buffer(capacity: request.utf8.count)
            out.writeString(request)
            context.writeAndFlush(wrapOutboundOut(out), promise: nil)
        }
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard step != .done else {
            context.fireChannelRead(data)
            return
        }
        var incoming = unwrapInboundIn(data)
        buffer.writeBuffer(&incoming)
        do {
            try advance(context: context)
        } catch {
            fail(error, context: context)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard step != .done else {
            context.fireErrorCaught(error)
            return
        }
        fail(error, context: context)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if step != .done {
            fail(ServerControlError.connectionFailed("the proxy closed the connection"),
                 context: context)
        }
        context.fireChannelInactive()
    }

    /// One pass over whatever has arrived so far
    private func advance(context: ChannelHandlerContext) throws {
        switch step {
        case .greeting: try readGreeting(context: context)
        case .authenticating: try readAuthentication(context: context)
        case .connecting: try readConnectReply(context: context)
        case .httpReply: try readHTTPReply(context: context)
        case .done: return
        }
    }

    private func readGreeting(context: ChannelHandlerContext) throws {
        guard buffer.readableBytes >= 2 else { return }
        let version: UInt8 = buffer.readInteger()!
        let method: UInt8 = buffer.readInteger()!
        guard version == 5 else {
            throw ServerControlError.connectionFailed("the proxy is not SOCKS5")
        }
        switch method {
        case 0:
            try sendConnect(context: context)
        case 2:
            try sendCredentials(context: context)
        default:
            throw ServerControlError.connectionFailed(
                "the proxy offered no authentication method this app can use")
        }
    }

    private func sendCredentials(context: ChannelHandlerContext) throws {
        guard let user = endpoint.username, !user.isEmpty else {
            throw ServerControlError.connectionFailed(
                "the proxy asked for a username and password")
        }
        let password = endpoint.password ?? ""
        guard let userLength = UInt8(exactly: user.utf8.count),
              let passwordLength = UInt8(exactly: password.utf8.count) else {
            throw ServerControlError.connectionFailed(
                "the proxy username or password is longer than SOCKS5 allows")
        }
        var out = context.channel.allocator.buffer(capacity: 3 + user.utf8.count)
        out.writeInteger(UInt8(1))
        out.writeInteger(userLength)
        out.writeString(user)
        out.writeInteger(passwordLength)
        out.writeString(password)
        step = .authenticating
        context.writeAndFlush(wrapOutboundOut(out), promise: nil)
    }

    private func readAuthentication(context: ChannelHandlerContext) throws {
        guard buffer.readableBytes >= 2 else { return }
        _ = buffer.readInteger(as: UInt8.self)
        let status: UInt8 = buffer.readInteger()!
        guard status == 0 else {
            throw ServerControlError.connectionFailed("the proxy refused the username or password")
        }
        try sendConnect(context: context)
    }

    private func readConnectReply(context: ChannelHandlerContext) throws {
        guard buffer.readableBytes >= 5 else { return }
        let head = buffer.getBytes(at: buffer.readerIndex, length: 5)!
        guard head[0] == 5 else {
            throw ServerControlError.connectionFailed("the proxy is not SOCKS5")
        }
        guard head[1] == 0 else {
            throw ServerControlError.connectionFailed(Self.socksFailure(head[1]))
        }
        let addressLength: Int
        switch head[3] {
        case 1: addressLength = 4
        case 3: addressLength = 1 + Int(head[4])
        case 4: addressLength = 16
        default:
            throw ServerControlError.connectionFailed("the proxy answered with an address this app cannot read")
        }
        let total = 4 + addressLength + 2
        guard buffer.readableBytes >= total else { return }
        buffer.moveReaderIndex(forwardBy: total)
        finish(context: context)
    }

    private func readHTTPReply(context: ChannelHandlerContext) throws {
        guard let text = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes),
              let headerEnd = text.range(of: "\r\n\r\n") else { return }
        let status = text[text.startIndex..<headerEnd.lowerBound]
            .split(separator: "\r\n").first.map(String.init) ?? ""
        let code = status.split(separator: " ").dropFirst().first.flatMap { Int($0) } ?? 0
        guard (200..<300).contains(code) else {
            throw ServerControlError.connectionFailed("the proxy refused: \(status)")
        }
        let consumed = text.distance(from: text.startIndex, to: headerEnd.upperBound)
        buffer.moveReaderIndex(forwardBy: consumed)
        finish(context: context)
    }

    private func sendConnect(context: ChannelHandlerContext) throws {
        guard let hostLength = UInt8(exactly: targetHost.utf8.count),
              let port = UInt16(exactly: targetPort) else {
            throw ServerControlError.connectionFailed("the address to reach is not valid for SOCKS5")
        }
        var out = context.channel.allocator.buffer(capacity: 7 + targetHost.utf8.count)
        out.writeInteger(UInt8(5))
        out.writeInteger(UInt8(1))    // CONNECT
        out.writeInteger(UInt8(0))
        out.writeInteger(UInt8(3))
        out.writeInteger(hostLength)
        out.writeString(targetHost)
        out.writeInteger(port)
        step = .connecting
        context.writeAndFlush(wrapOutboundOut(out), promise: nil)
    }

    /// The pipe is open
    private func finish(context: ChannelHandlerContext) {
        step = .done
        deadline?.cancel()
        if buffer.readableBytes > 0 {
            let rest = buffer.readSlice(length: buffer.readableBytes)!
            context.fireChannelRead(wrapInboundOut(rest))
        }
        promise?.succeed(())
        promise = nil
    }

    private func fail(_ error: Error, context: ChannelHandlerContext) {
        step = .done
        deadline?.cancel()
        promise?.fail(error)
        promise = nil
        context.close(promise: nil)
    }

    static func socksFailure(_ code: UInt8) -> String {
        switch code {
        case 1: return "the proxy failed"
        case 2: return "the proxy is not allowed to reach that host"
        case 3: return "the proxy says the network is unreachable"
        case 4: return "the proxy says the host is unreachable"
        case 5: return "the server refused the connection through the proxy"
        case 6: return "the connection through the proxy timed out"
        case 7: return "the proxy does not support this kind of connection"
        case 8: return "the proxy cannot use that address type"
        default: return "the proxy refused the connection (code \(code))"
        }
    }
}
