import Foundation
import XCTest
@testable import TVLink

/// One pairing and one session, every byte written down
final class TVLinkGoldenTests: XCTestCase {
    struct Golden: Codable, Equatable {
        struct Frame: Codable, Equatable {
            var from: String
            var hex: String
        }

        struct Message: Codable, Equatable {
            var from: String
            var json: String
        }

        var phone: TVPeer
        var tv: TVPeer
        var code: Int
        var pairingPhoneRandom: [String]
        var pairingFrames: [Frame]
        var pairingKey: String
        var sessionPhoneRandom: [String]
        var sessionFrames: [Frame]
        /// The decrypted requests and answers, as JSON text
        var sessionMessages: [Message]
    }

    static var url: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Resources/tvlink-golden.json")
    }

    static func make() throws -> Golden {
        let phone = TVPeer(id: "8C1F2E44-7A30-4B5D-9E61-0123456789AB", name: "orion")
        let tv = TVPeer(id: "tv-draco-0001", name: "Apple TV · draco")
        let code = TVPairingCode(value: 604_217)!

        let phoneRandom = ScriptedRandom(seed: "golden phone pairing")
        let run = PairingRun.run(phone: phone, tv: tv, typed: code, shown: code,
                                 phoneRandom: phoneRandom, tvRandom: ScriptedRandom(seed: "golden tv pairing"))
        if let failure = run.failure { throw failure }
        let pairingKey = try XCTUnwrap(run.phoneResult?.pairingKey)

        let sessionRandom = ScriptedRandom(seed: "golden phone session")
        let phoneSide = TVSessionPhone(phone: phone, tvID: tv.id, pairingKey: pairingKey, random: sessionRandom)
        let hello = phoneSide.hello()
        let accepted = try TVSessionTV(tv: tv, random: ScriptedRandom(seed: "golden tv session"))
            .accept(hello) { _ in pairingKey }
        var phoneChannel = try phoneSide.receive(accepted.reply)
        var tvChannel = accepted.channel

        var frames = [Golden.Frame(from: "phone", hex: try TVJSON.encode(hello).hex),
                      Golden.Frame(from: "tv", hex: try TVJSON.encode(accepted.reply).hex)]
        var messages: [Golden.Message] = []
        let server = TVSentServer(id: "6F0E0D0C-0B0A-4908-8706-050403020100", name: "draco",
                                  transfer: Data(#"{"deployment":{"name":"draco"}}"#.utf8))
        let exchange: [(TVMessage, TVMessage)] = [
            (TVMessage(t: .put, items: [server],
                       licence: TVLicenceVouch(active: true, plan: "yearly", expires: 1_900_000_000)),
             TVMessage(t: .servers, items: [server.withoutTransfer])),
            (TVMessage(t: .licence, licence: TVLicenceVouch(active: true, plan: "lifetime")), TVMessage(t: .ok)),
            (TVMessage(t: .list), TVMessage(t: .servers, items: [server.withoutTransfer])),
            (TVMessage(t: .unpair), TVMessage(t: .ok)),
        ]
        for (request, answer) in exchange {
            let sealedRequest = try phoneChannel.seal(request)
            XCTAssertEqual(try tvChannel.openMessage(sealedRequest), request)
            let sealedAnswer = try tvChannel.seal(answer)
            XCTAssertEqual(try phoneChannel.openMessage(sealedAnswer), answer)
            frames += [Golden.Frame(from: "phone", hex: sealedRequest.hex),
                       Golden.Frame(from: "tv", hex: sealedAnswer.hex)]
            messages += [Golden.Message(from: "phone", json: String(decoding: try TVJSON.encode(request), as: UTF8.self)),
                         Golden.Message(from: "tv", json: String(decoding: try TVJSON.encode(answer), as: UTF8.self))]
        }

        return Golden(phone: phone, tv: tv, code: code.value,
                      pairingPhoneRandom: phoneRandom.handedOut.map(\.hex),
                      pairingFrames: run.frames.map { Golden.Frame(from: $0.from, hex: $0.payload.hex) },
                      pairingKey: pairingKey.hex,
                      sessionPhoneRandom: sessionRandom.handedOut.map(\.hex),
                      sessionFrames: frames, sessionMessages: messages)
    }

    func testTheExchangeMatchesTheGoldenFile() throws {
        let made = try Self.make()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if ProcessInfo.processInfo.environment["GRYONIX_WRITE_TVLINK_GOLDEN"] == "1" {
            try encoder.encode(made).write(to: Self.url)
        }
        let stored = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: Self.url))
        XCTAssertEqual(stored, made, "the wire changed: Android must change with it")
    }

    func testTheScriptedRunIsRepeatable() throws {
        XCTAssertEqual(try Self.make(), try Self.make())
    }
}
