import CryptoKit
import Foundation
import XCTest
@testable import VPNProfile
import VPNTunnel

final class TunnelActivityFeedTests: XCTestCase {
    /// The app's ContentState, minus the stop-button flag
    private struct CardState: Decodable {
        var status: TunnelStatus
        var statistics: TunnelStatistics
    }

    private let ticket = TunnelActivityTicket(token: "card", relayURL: "https://relay.example.net",
                                              since: Date(timeIntervalSinceReferenceDate: 800_000_000))
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func decoded(_ body: [String: Any]?) throws -> CardState {
        let state = try XCTUnwrap(body?["state"])
        return try JSONDecoder().decode(CardState.self, from: JSONSerialization.data(withJSONObject: state))
    }

    func testTheCardReadsWhatTheTunnelSends() throws {
        var feed = TunnelActivityFeed()
        let sample = TunnelActivityFeed.Sample(received: 5000, sent: 1000, reconnecting: false)
        let state = try decoded(feed.next(sample, ticket: ticket, now: start))
        XCTAssertEqual(state.status, .connected(since: Date(timeIntervalSinceReferenceDate: 800_000_000)))
        XCTAssertEqual(state.statistics, TunnelStatistics(received: 5000, sent: 1000))
    }

    func testTrafficIsSentAtMostEveryThirtySeconds() {
        var feed = TunnelActivityFeed()
        let first = TunnelActivityFeed.Sample(received: 1, sent: 1, reconnecting: false)
        let more = TunnelActivityFeed.Sample(received: 2, sent: 2, reconnecting: false)
        XCTAssertNotNil(feed.next(first, ticket: ticket, now: start))
        XCTAssertNil(feed.next(more, ticket: ticket, now: start.addingTimeInterval(10)))
        XCTAssertNil(feed.next(first, ticket: ticket, now: start.addingTimeInterval(40)), "nothing new")
        let later = feed.next(more, ticket: ticket, now: start.addingTimeInterval(40))
        XCTAssertEqual(later?["urgent"] as? Bool, false)
    }

    func testAReconnectGoesOutAtOnceAndUrgently() throws {
        var feed = TunnelActivityFeed()
        _ = feed.next(.init(received: 1, sent: 1, reconnecting: false), ticket: ticket, now: start)
        let body = feed.next(.init(received: 1, sent: 1, reconnecting: true), ticket: ticket,
                             now: start.addingTimeInterval(2))
        XCTAssertEqual(body?["urgent"] as? Bool, true)
        XCTAssertEqual(try decoded(body).status,
                       .reasserting(since: Date(timeIntervalSinceReferenceDate: 800_000_000)))
    }

    func testTheEndClosesTheCardAndTimestampsRise() throws {
        var feed = TunnelActivityFeed()
        let sample = TunnelActivityFeed.Sample(received: 9, sent: 3, reconnecting: false)
        let update = feed.next(sample, ticket: ticket, now: start)
        let end = feed.end(sample, ticket: ticket, now: start)
        XCTAssertEqual(end["end"] as? Bool, true)
        XCTAssertEqual(try decoded(end).status, .off)
        XCTAssertGreaterThan(try XCTUnwrap(end["timestamp"] as? Int), try XCTUnwrap(update?["timestamp"] as? Int))
    }

    func testTheSignatureIsTheRelaysMessage() throws {
        let key = Curve25519.Signing.PrivateKey()
        let body = Data("{}".utf8)
        let headers = TunnelActivityRelay.signature(method: "POST", path: "/v1/servers/x/live", body: body,
                                                    key: key, now: start)
        XCTAssertEqual(headers["x-gryonix-timestamp"], "1800000000")
        let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let message = Data("POST\n/v1/servers/x/live\n1800000000\n\(digest)".utf8)
        let signature = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(headers["x-gryonix-signature"])))
        XCTAssertTrue(key.publicKey.isValidSignature(signature, for: message))
    }

    func testTheTicketSurvivesTheAppGroupFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ticket.save(to: url)
        XCTAssertEqual(TunnelActivityTicket.load(from: url), ticket)
        TunnelActivityTicket.clear(at: url)
        XCTAssertNil(TunnelActivityTicket.load(from: url))
    }
}
