import Citadel
import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import ServerControl
import XCTest
@testable import ServerControlSSH

final class SSHDialTests: XCTestCase {
    /// A loopback server that counts connections and reports closes
    private final class FakeSSHD: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = ByteBuffer

        let banner: String?
        let accepted = NIOLockedValueBox(0)
        let closed = NIOLockedValueBox(0)

        init(banner: String?) { self.banner = banner }

        func channelActive(context: ChannelHandlerContext) {
            accepted.withLockedValue { $0 += 1 }
            guard let banner else {
                context.close(promise: nil)
                return
            }
            context.writeAndFlush(NIOAny(context.channel.allocator.buffer(string: banner)), promise: nil)
        }

        func channelInactive(context: ChannelHandlerContext) {
            closed.withLockedValue { $0 += 1 }
        }
    }

    private func serve(_ sshd: FakeSSHD) async throws -> Channel {
        try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { $0.pipeline.addHandler(sshd) }
            .bind(host: "127.0.0.1", port: 0)
            .get()
    }

    private func settings(port: Int) -> SSHClientSettings {
        SSHClientSettings(host: "127.0.0.1", port: port,
                          authenticationMethod: { .passwordBased(username: "u", password: "p") },
                          hostKeyValidator: .acceptAnything())
    }

    func testASilentHangUpIsRedialledThenExplained() async throws {
        let sshd = FakeSSHD(banner: nil)
        let server = try await serve(sshd)
        defer { server.close(promise: nil) }
        do {
            _ = try await SSHDial.connect(settings(port: server.localAddress!.port!),
                                          pauses: [.milliseconds(10), .milliseconds(10)])
            XCTFail("a server that always hangs up cannot sign in")
        } catch ServerControlError.connectionFailed(let reason) {
            XCTAssertTrue(reason.contains("before answering"), reason)
        }
        XCTAssertEqual(sshd.accepted.withLockedValue { $0 }, 3)
    }

    func testACancelledSignInClosesTheServersSocket() async throws {
        let sshd = FakeSSHD(banner: "SSH-2.0-OpenSSH_10.0\r\n")
        let server = try await serve(sshd)
        defer { server.close(promise: nil) }
        let port = server.localAddress!.port!
        let attempt = Task { try await SSHDial.connect(settings(port: port), pauses: []) }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(sshd.accepted.withLockedValue { $0 }, 1)
        XCTAssertEqual(sshd.closed.withLockedValue { $0 }, 0)
        attempt.cancel()
        _ = try? await attempt.value
        for _ in 0..<20 where sshd.closed.withLockedValue({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(sshd.closed.withLockedValue { $0 }, 1, "the server must not wait out its grace time")
    }
}
