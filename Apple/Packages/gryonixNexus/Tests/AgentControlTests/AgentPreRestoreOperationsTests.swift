import AgentClient
import Foundation
import XCTest
@testable import AgentControl

private struct Answering: AgentTransport {
    let onUnary: @Sendable (String, Data) async throws -> Data

    func unary(path: String, request: Data) async throws -> Data {
        try await onUnary(path, request)
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private func wireCopy(_ path: String, bytes: UInt64, at seconds: Int64,
                  known: Bool = true) -> Gryonixnexusd_V1_PreRestoreCopy {
    var message = Gryonixnexusd_V1_PreRestoreCopy()
    message.serviceID = "nextcloud"
    message.path = path
    message.sizeBytes = bytes
    message.sizeKnown = known
    message.movedAsideUnix = seconds
    return message
}

private func encoded(_ copies: [Gryonixnexusd_V1_PreRestoreCopy]) -> Data {
    var list = Gryonixnexusd_V1_PreRestoreCopyList()
    list.copies = copies
    return (try? list.serializedBytes()) ?? Data()
}

final class AgentPreRestoreOperationsTests: XCTestCase {
    func testTheListAsksForOneServiceAndComesBackNewestFirst() async throws {
        let asked = LockedBox<Gryonixnexusd_V1_ListPreRestoreCopiesRequest>()
        let operations = AgentPreRestoreOperations(client: AgentClient(transport: Answering(onUnary: { path, request in
            XCTAssertEqual(path, "/gryonixnexusd.v1.Restore/ListPreRestoreCopies")
            asked.value = try? Gryonixnexusd_V1_ListPreRestoreCopiesRequest(serializedBytes: request)
            return encoded([
                wireCopy("/opt/nextcloud/data.pre-restore-20260901-100000", bytes: 5_000, at: 1_788_000_000),
                wireCopy("/opt/nextcloud/data.pre-restore-20261001-100000", bytes: 9_000, at: 1_790_000_000)
            ])
        })))

        let copies = try await operations.copies(serviceID: "nextcloud")

        XCTAssertEqual(asked.value?.serviceID, "nextcloud")
        XCTAssertEqual(copies.map(\.sizeBytes), [9_000, 5_000])
        XCTAssertEqual(copies.first?.name, "data.pre-restore-20261001-100000")
        XCTAssertEqual(copies.first?.movedAside, Date(timeIntervalSince1970: 1_790_000_000))
    }

    func testDeletingSendsTheCopysOwnPathAndReturnsWhatIsLeft() async throws {
        let sent = LockedBox<Gryonixnexusd_V1_DeletePreRestoreCopyRequest>()
        let target = PreRestoreCopy(wireCopy("/opt/nextcloud/data.pre-restore-20261001-100000", bytes: 9_000, at: 1))
        let operations = AgentPreRestoreOperations(client: AgentClient(transport: Answering(onUnary: { path, request in
            XCTAssertEqual(path, "/gryonixnexusd.v1.Restore/DeletePreRestoreCopy")
            sent.value = try? Gryonixnexusd_V1_DeletePreRestoreCopyRequest(serializedBytes: request)
            return encoded([])
        })))

        let left = try await operations.delete(target)

        XCTAssertEqual(sent.value?.path, "/opt/nextcloud/data.pre-restore-20261001-100000")
        XCTAssertTrue(left.isEmpty)
    }

    func testASizeThatRanOutOfTimeIsFlaggedUnknown() {
        let measured = PreRestoreCopy(wireCopy("/srv/a.pre-restore-1", bytes: 10, at: 1))
        let unmeasured = PreRestoreCopy(wireCopy("/srv/b.pre-restore-1", bytes: 0, at: 1, known: false))
        XCTAssertTrue(measured.sizeKnown)
        XCTAssertFalse(unmeasured.sizeKnown)
    }
}
