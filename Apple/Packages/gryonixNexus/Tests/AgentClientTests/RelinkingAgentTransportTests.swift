import XCTest
@testable import AgentClient

private struct DeadLink: Error {}

/// Counts links handed out; the first `dead` of them fail
private final class Links: @unchecked Sendable {
    private let lock = NSLock()
    private var made = 0
    private(set) var dropped = 0
    let dead: Int
    let error: Error

    init(dead: Int, error: Error = DeadLink()) {
        self.dead = dead
        self.error = error
    }

    func next() -> any AgentTransport {
        lock.lock(); defer { lock.unlock() }
        made += 1
        return StubLink(fails: made <= dead ? error : nil)
    }

    func drop() {
        lock.lock(); dropped += 1; lock.unlock()
    }

    var transport: RelinkingAgentTransport {
        RelinkingAgentTransport(link: { self.next() },
                                isDeadLink: { $0 is DeadLink },
                                dropLink: { self.drop() })
    }
}

private struct StubLink: AgentTransport {
    let fails: Error?

    func unary(path: String, request: Data) async throws -> Data {
        if let fails { throw fails }
        return Data(path.utf8)
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            if let fails { return continuation.finish(throwing: fails) }
            continuation.yield(Data(path.utf8))
            continuation.finish()
        }
    }
}

final class RelinkingAgentTransportTests: XCTestCase {
    func testUnaryRetriesOnceOnAFreshLink() async throws {
        let links = Links(dead: 1)
        let answer = try await links.transport.unary(path: "/a", request: Data())
        XCTAssertEqual(answer, Data("/a".utf8))
        XCTAssertEqual(links.dropped, 1)
    }

    func testUnaryGivesUpAfterTheSecondDeadLink() async {
        let links = Links(dead: 2)
        do {
            _ = try await links.transport.unary(path: "/a", request: Data())
            XCTFail("expected the dead link to surface")
        } catch {
            XCTAssertTrue(error is DeadLink)
        }
    }

    func testOtherFailuresAreNotRetried() async {
        let links = Links(dead: 1, error: AgentError.transport("refused"))
        do {
            _ = try await links.transport.unary(path: "/a", request: Data())
            XCTFail("expected the failure")
        } catch {
            XCTAssertEqual(error as? AgentError, .transport("refused"))
            XCTAssertEqual(links.dropped, 0)
        }
    }

    func testStreamRetriesWhenNothingCameThrough() async throws {
        let links = Links(dead: 1)
        var frames: [Data] = []
        for try await frame in links.transport.serverStream(path: "/s", request: Data()) {
            frames.append(frame)
        }
        XCTAssertEqual(frames, [Data("/s".utf8)])
        XCTAssertEqual(links.dropped, 1)
    }
}
