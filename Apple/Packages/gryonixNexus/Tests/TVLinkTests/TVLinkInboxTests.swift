import Foundation
import XCTest
@testable import TVLink

final class TVLinkInboxTests: XCTestCase {
    private var directory: URL!
    private var phones: TVPhoneStore!
    private let receiver = TVLinkLoopbackTests.Receiver()
    private var inbox: TVLinkInbox!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        phones = TVPhoneStore(fileURL: directory.appendingPathComponent("phones.json"), secrets: TVMemorySecrets())
        inbox = TVLinkInbox(servers: receiver, phones: phones)
        try phones.save(TVPairedPhone(id: "a", name: "orion", pairedAt: now, lastSeen: now), pairingKey: Data([1]))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAnUnknownPhoneIsRefused() {
        XCTAssertEqual(inbox.handle(TVMessage(t: .list), from: "b").code, "unknown-phone")
    }

    func testSentServersAreListedWithoutTheirBundles() {
        let server = TVSentServer(id: "s1", name: "draco", transfer: Data([9]))
        _ = inbox.handle(TVMessage(t: .put, items: [server]), from: "a", now: now)
        _ = inbox.handle(TVMessage(t: .put, items: [server]), from: "a", now: now)
        XCTAssertEqual(inbox.handle(TVMessage(t: .list), from: "a").items, [server.withoutTransfer])
    }

    func testAnUnreadableServerIsRefused() {
        let answer = inbox.handle(TVMessage(t: .put, items: [TVSentServer(id: "x", name: "", transfer: nil)]),
                                  from: "a")
        XCTAssertEqual(answer.code, "unusable")
        XCTAssertEqual(answer.items?.first?.id, "x")
    }

    func testEveryRequestRefreshesTheLicenseWord() {
        let later = now.addingTimeInterval(60)
        _ = inbox.handle(TVMessage(t: .licence, licence: TVLicenceVouch(active: true, plan: "lifetime")),
                         from: "a", now: later)
        XCTAssertEqual(phones.record("a")?.licenceAt, later)
        XCTAssertEqual(phones.record("a")?.licence?.plan, "lifetime")
    }

    func testUnpairForgetsThePhone() {
        XCTAssertEqual(inbox.handle(TVMessage(t: .unpair), from: "a").t, .ok)
        XCTAssertNil(phones.record("a"))
        XCTAssertNil(phones.pairingKey("a"))
    }
}
