import Citadel
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import NIOSSH
import ServerControl

/// Pipes bytes between a local socket and an SSH channel
final class ForwardGlueHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private var partner: ForwardGlueHandler?
    private var context: ChannelHandlerContext?

    static func matchedPair() -> (ForwardGlueHandler, ForwardGlueHandler) {
        let first = ForwardGlueHandler()
        let second = ForwardGlueHandler()
        first.partner = second
        second.partner = first
        return (first, second)
    }

    func handlerAdded(context: ChannelHandlerContext) { self.context = context }

    func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
        partner = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        partner?.context?.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        partner?.context?.close(promise: nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

/// A local listener forwarding through SSH
public final class PortForwarder: @unchecked Sendable {
    private let clientProvider: @Sendable () async throws -> SSHClient
    private let counter = NIOLockedValueBox(0)
    private var listener: Channel?

    public init(clientProvider: @escaping @Sendable () async throws -> SSHClient) {
        self.clientProvider = clientProvider
    }

    public var connections: Int { counter.withLockedValue { $0 } }

    public func start(localPort: Int, remoteHost: String, remotePort: Int) async throws {
        let provider = clientProvider
        let counter = counter
        let bootstrap = ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.autoRead, value: false)
            .childChannelInitializer { local in
                Self.bridge(local, provider: provider, host: remoteHost, port: remotePort, counter: counter)
            }
        listener = try await bootstrap.bind(host: "127.0.0.1", port: localPort).get()
    }

    public func stop() async {
        try? await listener?.close()
        listener = nil
    }

    private static func bridge(_ local: Channel, provider: @escaping @Sendable () async throws -> SSHClient,
                               host: String, port: Int,
                               counter: NIOLockedValueBox<Int>) -> EventLoopFuture<Void> {
        let done = local.eventLoop.makePromise(of: Void.self)
        Task {
            do {
                let client = try await provider()
                let (localGlue, remoteGlue) = ForwardGlueHandler.matchedPair()
                let origin = try local.remoteAddress ?? SocketAddress(ipAddress: "127.0.0.1", port: 0)
                let remote = try await client.createDirectTCPIPChannel(
                    using: SSHChannelType.DirectTCPIP(targetHost: host, targetPort: port,
                                                      originatorAddress: origin)
                ) { channel in
                    channel.setOption(ChannelOptions.autoRead, value: false).flatMap {
                        channel.pipeline.addHandler(remoteGlue)
                    }
                }
                try await local.pipeline.addHandler(localGlue).get()
                counter.withLockedValue { $0 += 1 }
                local.closeFuture.whenComplete { _ in counter.withLockedValue { $0 -= 1 } }
                try await local.setOption(ChannelOptions.autoRead, value: true).get()
                try await remote.setOption(ChannelOptions.autoRead, value: true).get()
                local.read()
                done.succeed(())
            } catch {
                local.close(promise: nil)
                done.fail(error)
            }
        }
        return done.futureResult
    }
}
