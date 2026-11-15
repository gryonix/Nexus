import Foundation
import XCTest
@testable import ServerControl

final class QuickTransferTicketTests: XCTestCase {
    func testTheTextRoundTrips() throws {
        let ticket = QuickTransferTicket.fresh(port: 50123, addresses: ["198.51.100.20", "203.0.113.4"])
        XCTAssertEqual(QuickTransferTicket(text: ticket.text), ticket)
        XCTAssertTrue(ticket.text.hasPrefix("GXT1;"))
    }

    func testForeignTextIsRefused() {
        XCTAssertNil(QuickTransferTicket(text: "WIFI:S:home;T:WPA;P:secret;;"))
        XCTAssertNil(QuickTransferTicket(text: "GXT1;AAAA;BBBB;1;"))
        XCTAssertNil(QuickTransferTicket(text: "GXT2;" + String(repeating: "A", count: 22) + ";x;1;"))
    }

    func testAddressesThatAreNotIPv4AreDropped() throws {
        var ticket = QuickTransferTicket.fresh(port: 1, addresses: [])
        ticket.addresses = ["198.51.100.20", "example.net", "300.1.1.1", "fe80::1"]
        XCTAssertEqual(QuickTransferTicket(text: ticket.text)?.addresses, ["198.51.100.20"])
    }

    func testTheBluetoothServiceComesFromTheSession() {
        let ticket = QuickTransferTicket(session: Data(0..<16), key: Data(repeating: 1, count: 32),
                                         port: 1, addresses: [])
        XCTAssertEqual(ticket.bluetoothService.uuidString, "00010203-0405-0607-0809-0A0B0C0D0E0F")
    }

    func testAnEmptyAddressListStillParses() {
        let ticket = QuickTransferTicket.fresh(port: 0, addresses: [])
        XCTAssertEqual(QuickTransferTicket(text: ticket.text)?.addresses, [])
    }
}

final class QuickTransferCipherTests: XCTestCase {
    let cipher = QuickTransferCipher(key: Data(0..<32))

    func testSealedFramesOpenOnlyWithTheSameDirectionAndSequence() throws {
        let sealed = try cipher.seal(Data("hi".utf8), direction: .toSender, sequence: 3)
        XCTAssertEqual(try cipher.open(sealed, direction: .toSender, sequence: 3), Data("hi".utf8))
        XCTAssertThrowsError(try cipher.open(sealed, direction: .toReceiver, sequence: 3))
        XCTAssertThrowsError(try cipher.open(sealed, direction: .toSender, sequence: 4))
    }

    func testAnotherKeyCannotOpenTheFrame() throws {
        let sealed = try cipher.seal(Data("hi".utf8), direction: .toSender, sequence: 0)
        let other = QuickTransferCipher(key: Data(repeating: 7, count: 32))
        XCTAssertThrowsError(try other.open(sealed, direction: .toSender, sequence: 0)) {
            XCTAssertEqual($0 as? QuickTransferError, .notOurs)
        }
    }

    /// The same bytes the Kotlin side checks
    func testTheSharedVectorMatches() throws {
        let sealed = try cipher.seal(Data("hello GXT1".utf8), direction: .toSender, sequence: 0, nonce: Data(0..<12))
        XCTAssertEqual(sealed.map { String(format: "%02x", $0) }.joined(), Self.vector)
        XCTAssertEqual(cipher.code(for: Data(0..<16)), Self.code)
    }

    func testCompressedMessagesMatchTheKotlinVector() throws {
        let json = Data(#"{"kind":"accept"}"#.utf8)
        let packed = try QuickTransferDeflate.compress(json)
        XCTAssertEqual(packed.map { String(format: "%02x", $0) }.joined(), Self.deflated)
        XCTAssertEqual(try QuickTransferDeflate.decompress(packed), json)
    }

    func testTheCodeIsFourDigits() {
        for _ in 0..<50 {
            let code = cipher.code(for: TransferSeal.randomBytes(16))
            XCTAssertEqual(code.count, 4)
            XCTAssertTrue(code.allSatisfy(\.isNumber))
        }
    }

    static let vector = "000102030405060708090a0b2f67ba77aac58543d9707e4d63576133e433ae6a2c1d84c9c746"
    static let code = "5944"
    static let deflated = "ab56cacecc4b51b2524a4c4e4e2d2851aa0500"
}

final class QuickTransferFramesTests: XCTestCase {
    func testPayloadsSurviveAnySplit() throws {
        let payloads = [Data("one".utf8), Data(repeating: 9, count: 1000), Data("three".utf8)]
        let stream = payloads.map(QuickTransferFrames.frame).reduce(Data(), +)
        var frames = QuickTransferFrames()
        var out: [Data] = []
        var index = stream.startIndex
        while index < stream.endIndex {
            let end = min(index + 7, stream.endIndex)
            out += try frames.append(stream[index..<end])
            index = end
        }
        XCTAssertEqual(out, payloads)
    }

    func testAnOversizedLengthIsRefused() {
        var frames = QuickTransferFrames()
        XCTAssertThrowsError(try frames.append(Data([0x7f, 0xff, 0xff, 0xff])))
    }
}

final class QuickTransferFlowTests: XCTestCase {
    func testTheWholeConversationOverMemory() async throws {
        let (a, b) = MemoryLink.pair()
        try await converse(senderLink: a, receiverLink: b)
    }

    func testTheWholeConversationOverTCP() async throws {
        let listener = try QuickTransferTCPListener()
        let accepted = AsyncStream<QuickTransferTCPLink>.makeStream()
        let port = try await listener.start { accepted.continuation.yield($0) }
        defer { listener.stop() }
        let receiverLink = try await QuickTransferTCPLink.connectFirst(to: ["127.0.0.1"], port: port)
        var iterator = accepted.stream.makeAsyncIterator()
        let next = await iterator.next()
        let senderLink = try XCTUnwrap(next)
        try await converse(senderLink: senderLink, receiverLink: receiverLink)
    }

    func testADeclineReachesTheReceiver() async throws {
        let (a, b) = MemoryLink.pair()
        let key = TransferSeal.randomBytes(32)
        let sender = QuickTransferChannel(link: a, key: key, role: .sender)
        let receiver = QuickTransferChannel(link: b, key: key, role: .receiver)
        _ = try await QuickTransferFlow.knock(receiver, device: "Phone")
        _ = try await QuickTransferFlow.greet(sender)
        await QuickTransferFlow.decline(sender)
        do {
            try await QuickTransferFlow.awaitAnswer(receiver)
            XCTFail("expected a decline")
        } catch {
            XCTAssertEqual(error as? QuickTransferError, .declined)
        }
    }

    func testAHelloUnderAnotherKeyIsNotOurs() async throws {
        let (a, b) = MemoryLink.pair()
        let sender = QuickTransferChannel(link: a, key: TransferSeal.randomBytes(32), role: .sender)
        let stranger = QuickTransferChannel(link: b, key: TransferSeal.randomBytes(32), role: .receiver)
        _ = try await QuickTransferFlow.knock(stranger, device: "Stranger")
        do {
            _ = try await QuickTransferFlow.greet(sender)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? QuickTransferError, .notOurs)
        }
    }

    func testTheRaceTakesTheFirstLinkAndClosesTheLate() async throws {
        let (fast, _) = MemoryLink.pair()
        let (slow, slowPeer) = MemoryLink.pair()
        let winner = try await QuickTransferRace.first(of: [
            { throw QuickTransferError.closed },
            { fast },
            {
                try? await Task.sleep(nanoseconds: 50_000_000)
                return slow
            },
        ], timeout: 5)
        XCTAssertTrue(winner === fast)
        do {
            _ = try await slowPeer.receive()
            XCTFail("the late link should be closed")
        } catch {
            XCTAssertEqual(error as? QuickTransferError, .closed)
        }
    }

    func testTheRaceGivesUpWhenEveryAttemptFails() async {
        do {
            _ = try await QuickTransferRace.first(of: [{ throw QuickTransferError.closed }], timeout: 5)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? QuickTransferError, .closed)
        }
    }

    private func converse(senderLink: any QuickTransferLink, receiverLink: any QuickTransferLink) async throws {
        let key = TransferSeal.randomBytes(32)
        let sender = QuickTransferChannel(link: senderLink, key: key, role: .sender)
        let receiver = QuickTransferChannel(link: receiverLink, key: key, role: .receiver)
        let servers = [String(repeating: "{\"deployment\":1}", count: 2000), "{}"]
        let shown = try await QuickTransferFlow.knock(receiver, device: "iPad")
        let hello = try await QuickTransferFlow.greet(sender)
        XCTAssertEqual(hello, QuickTransferFlow.Hello(device: "iPad", code: shown))
        try await QuickTransferFlow.accept(sender)
        try await QuickTransferFlow.awaitAnswer(receiver)
        async let delivered = QuickTransferFlow.deliver(sender, servers: servers)
        let received = try await QuickTransferFlow.collect(receiver)
        XCTAssertEqual(received, servers)
        let count = try await delivered
        XCTAssertEqual(count, 2)
    }
}

/// Two in-memory ends of a link
final class MemoryLink: QuickTransferLink, @unchecked Sendable {
    private let inbox = AsyncStream<Data>.makeStream()
    private var iterator: AsyncStream<Data>.Iterator
    weak var peer: MemoryLink?

    init() { iterator = inbox.stream.makeAsyncIterator() }

    static func pair() -> (MemoryLink, MemoryLink) {
        let a = MemoryLink()
        let b = MemoryLink()
        a.peer = b
        b.peer = a
        return (a, b)
    }

    func send(_ payload: Data) async throws {
        guard let peer else { throw QuickTransferError.closed }
        peer.inbox.continuation.yield(payload)
    }

    func receive() async throws -> Data {
        guard let next = await iterator.next() else { throw QuickTransferError.closed }
        return next
    }

    func close() { peer?.inbox.continuation.finish() }
}
