import Foundation
import Network
import XCTest
@testable import TVLink

final class TVLinkLoopbackTests: XCTestCase {
    final class Receiver: TVServerReceiving, @unchecked Sendable {
        let lock = NSLock()
        var received: [TVSentServer] = []

        func receive(_ items: [TVSentServer]) throws {
            if let bad = items.first(where: { $0.transfer == nil }) { throw TVLinkStoreError.unusable(bad.id) }
            lock.withLock { received += items }
        }
    }

    final class Host: TVLinkHost, @unchecked Sendable {
        let lock = NSLock()
        var code: TVPairingCode
        var codesDrawn = 0
        var pairingsEnded = 0
        let phones: TVPhoneStore
        let servers = Receiver()
        let inbox: TVLinkInbox

        init(directory: URL, code: TVPairingCode) {
            self.code = code
            phones = TVPhoneStore(fileURL: directory.appendingPathComponent("phones.json"), secrets: TVMemorySecrets())
            inbox = TVLinkInbox(servers: servers, phones: phones)
        }

        func pairingCode(for phone: TVPeer) async -> TVPairingCode {
            lock.withLock { code }
        }

        func pairingEnded(phone: TVPeer, result: TVPairingResult?, codeTried: Bool) async {
            lock.withLock {
                pairingsEnded += 1
                if result == nil, codeTried {
                    codesDrawn += 1
                    code = TVPairingCode.random(SystemTVLinkRandom())
                }
            }
            if let result {
                try? phones.save(TVPairedPhone(id: phone.id, name: phone.name, pairedAt: Date(), lastSeen: Date()),
                                 pairingKey: result.pairingKey)
            }
        }

        func pairingKey(for phoneID: String) async -> Data? {
            phones.pairingKey(phoneID)
        }

        func handle(_ request: TVMessage, from phoneID: String) async -> TVMessage {
            inbox.handle(request, from: phoneID)
        }
    }

    let phone = TVPeer(id: "phone-orion", name: "orion")
    let tv = TVPeer(id: "tv-draco", name: "draco")
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func local(_ port: UInt16) -> NWEndpoint {
        TVAddress(host: "127.0.0.1", port: port).endpoint
    }

    func testPairSendServersVouchAndUnpairOverTCP() async throws {
        let code = TVPairingCode(value: 315_270)!
        let host = Host(directory: directory, code: code)
        let server = TVLinkServer(tv: tv, host: host, advertise: false)
        let port = try await server.start(port: nil)
        defer { server.stop() }

        let attempt = try await TVPairingAttempt.start(local(port), phone: phone)
        let paired = try await attempt.enter(code)
        XCTAssertEqual(paired.peer, tv)
        try await waitUntil { host.phones.pairingKey(self.phone.id) != nil }

        let sent = TVSentServer(id: UUID().uuidString, name: "draco", transfer: Data("bundle".utf8))
        let answers = try await TVLinkClient.exchange(
            [TVMessage(t: .put, items: [sent], licence: TVLicenceVouch(active: true, plan: "lifetime")),
             TVMessage(t: .list)],
            at: local(port), phone: phone, tvID: tv.id, pairingKey: paired.pairingKey)
        XCTAssertEqual(answers.map(\.t), [.servers, .servers])
        XCTAssertEqual(answers[1].items, [sent.withoutTransfer], "a bundle never travels back")
        XCTAssertEqual(host.servers.received, [sent])
        XCTAssertEqual(host.phones.record(phone.id)?.licence?.plan, "lifetime")

        let gone = try await TVLinkClient.exchange([TVMessage(t: .unpair)], at: local(port), phone: phone,
                                                   tvID: tv.id, pairingKey: paired.pairingKey)
        XCTAssertEqual(gone.first?.t, .ok)
        XCTAssertNil(host.phones.record(phone.id))
        do {
            _ = try await TVLinkClient.exchange([TVMessage(t: .licence)], at: local(port), phone: phone,
                                                tvID: tv.id, pairingKey: paired.pairingKey)
            XCTFail("an unpaired phone must be refused")
        } catch {
            XCTAssertEqual(error as? TVHandshakeError, .refused(.unknownPhone))
        }
    }

    func testAWrongCodeFailsAndTheTVDrawsANewOne() async throws {
        let host = Host(directory: directory, code: TVPairingCode(value: 315_270)!)
        let server = TVLinkServer(tv: tv, host: host, advertise: false)
        let port = try await server.start(port: nil)
        defer { server.stop() }

        let attempt = try await TVPairingAttempt.start(local(port), phone: phone)
        do {
            _ = try await attempt.enter(TVPairingCode(value: 315_271)!)
            XCTFail("the wrong code paired")
        } catch {
            XCTAssertEqual(error as? TVHandshakeError, .refused(.wrongCode))
        }
        try await waitUntil { host.lock.withLock { host.codesDrawn } == 1 }
        XCTAssertNil(host.phones.pairingKey(phone.id))
    }

    func testAPhoneThatLeavesBeforeTypingKeepsTheCode() async throws {
        let code = TVPairingCode(value: 315_270)!
        let host = Host(directory: directory, code: code)
        let server = TVLinkServer(tv: tv, host: host, advertise: false)
        let port = try await server.start(port: nil)
        defer { server.stop() }

        let left = try await TVPairingAttempt.start(local(port), phone: phone)
        await left.cancel()
        try await waitUntil { host.lock.withLock { host.pairingsEnded } == 1 }
        XCTAssertEqual(host.lock.withLock { host.codesDrawn }, 0)

        let attempt = try await TVPairingAttempt.start(local(port), phone: phone)
        let paired = try await attempt.enter(code)
        XCTAssertEqual(paired.peer, tv)
    }

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { XCTFail("condition not met in time"); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
