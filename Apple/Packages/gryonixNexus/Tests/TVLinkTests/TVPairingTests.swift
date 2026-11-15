import CryptoKit
import Foundation
import XCTest
@testable import TVLink

final class TVPairingTests: XCTestCase {
    let phone = TVPeer(id: "phone-orion", name: "orion")
    let tv = TVPeer(id: "tv-draco", name: "draco")
    let code = TVPairingCode(value: 482_913)!

    func testTheRightCodePairsBothSidesOnTheSameKey() throws {
        let run = PairingRun.run(phone: phone, tv: tv, typed: code, shown: code)
        XCTAssertNil(run.failure)
        let phoneSide = try XCTUnwrap(run.phoneResult)
        let tvSide = try XCTUnwrap(run.tvResult)
        XCTAssertEqual(phoneSide.pairingKey, tvSide.pairingKey)
        XCTAssertEqual(phoneSide.pairingKey.count, 32)
        XCTAssertEqual(phoneSide.peer, tv)
        XCTAssertEqual(tvSide.peer, phone)
        XCTAssertEqual(run.frames.count, 2 + 4 * TVPairingCode.bitCount + 2)
    }

    func testEveryWrongCodeIsRefusedByTheTV() {
        for wrong in [code.value ^ 1, code.value ^ (1 << 10), code.value ^ (1 << 19)] {
            let run = PairingRun.run(phone: phone, tv: tv, typed: TVPairingCode(value: wrong % 1_000_000)!,
                                     shown: code)
            XCTAssertNil(run.phoneResult)
            XCTAssertNil(run.tvResult)
            XCTAssertEqual(run.failure as? TVHandshakeError, .refused(.wrongCode), "code \(wrong)")
        }
    }

    func testTheCodeNeverAppearsOnTheWire() throws {
        let run = PairingRun.run(phone: phone, tv: tv, typed: code, shown: code)
        let everything = run.frames.map(\.payload).reduce(Data(), +)
        XCTAssertNil(everything.range(of: Data(code.digits.utf8)))
    }

    func testAManInTheMiddleWithoutTheCodeIsCaught() throws {
        let guess = TVPairingCode(value: 0)!
        var phoneSide = TVPairingPhone(phone: phone)
        var attackerAsTV = TVPairingTV(tv: tv, code: guess)
        var attackerAsPhone = TVPairingPhone(phone: phone)
        var tvSide = TVPairingTV(tv: tv, code: code)

        _ = try phoneSide.receive(try attackerAsTV.receive(phoneSide.hello()))
        _ = try attackerAsPhone.receive(try tvSide.receive(attackerAsPhone.hello()))
        var towardsAttacker = try phoneSide.enter(code)
        var towardsTV = try attackerAsPhone.enter(guess)

        var phoneCaught = false
        var tvCaught = false
        for _ in 0..<(4 * TVPairingCode.bitCount) where !(phoneCaught && tvCaught) {
            if !phoneCaught {
                do {
                    let answer = try attackerAsTV.receive(towardsAttacker)
                    if case .send(let next) = try phoneSide.receive(answer) { towardsAttacker = next }
                } catch { phoneCaught = true }
            }
            if !tvCaught {
                do {
                    let answer = try tvSide.receive(towardsTV)
                    if case .send(let next) = try attackerAsPhone.receive(answer) { towardsTV = next }
                } catch { tvCaught = true }
            }
        }
        XCTAssertTrue(phoneCaught)
        XCTAssertTrue(tvCaught)
    }

    func testASessionOpensOnlyWithThePairingKey() throws {
        let run = PairingRun.run(phone: phone, tv: tv, typed: code, shown: code)
        let key = try XCTUnwrap(run.phoneResult?.pairingKey)
        let phoneSide = TVSessionPhone(phone: phone, tvID: tv.id, pairingKey: key)
        let accepted = try TVSessionTV(tv: tv).accept(phoneSide.hello()) { $0 == self.phone.id ? key : nil }
        XCTAssertEqual(accepted.phoneID, phone.id)
        var phoneChannel = try phoneSide.receive(accepted.reply)
        var tvChannel = accepted.channel

        let request = TVMessage(t: .list)
        XCTAssertEqual(try tvChannel.openMessage(phoneChannel.seal(request)), request)
        let answer = TVMessage(t: .servers, items: [])
        XCTAssertEqual(try phoneChannel.openMessage(tvChannel.seal(answer)), answer)

        // A phone with another key cannot be read
        let impostor = TVSessionPhone(phone: phone, tvID: tv.id, pairingKey: Data(repeating: 1, count: 32))
        let other = try TVSessionTV(tv: tv).accept(impostor.hello()) { _ in key }
        var impostorChannel = try impostor.receive(other.reply)
        var tvSeesImpostor = other.channel
        XCTAssertThrowsError(try tvSeesImpostor.openMessage(impostorChannel.seal(request)))
    }

    func testAnUnknownPhoneIsToldSo() {
        let phoneSide = TVSessionPhone(phone: phone, tvID: tv.id, pairingKey: Data(count: 32))
        XCTAssertThrowsError(try TVSessionTV(tv: tv).accept(phoneSide.hello()) { _ in nil }) { error in
            XCTAssertEqual(error as? TVHandshakeError, .refused(.unknownPhone))
        }
    }

    func testThePhoneRefusesAnotherTV() throws {
        let key = Data(repeating: 9, count: 32)
        let phoneSide = TVSessionPhone(phone: phone, tvID: "tv-somewhere-else", pairingKey: key)
        let accepted = try TVSessionTV(tv: tv).accept(phoneSide.hello()) { _ in key }
        XCTAssertThrowsError(try phoneSide.receive(accepted.reply)) { error in
            XCTAssertEqual(error as? TVHandshakeError, .wrongPeer)
        }
    }

    func testReplayedReorderedOrAlteredFramesDoNotOpen() throws {
        let keys = TVHandshakeKeys(phoneToTV: Data(repeating: 1, count: 32),
                                   tvToPhone: Data(repeating: 2, count: 32), pairingKey: nil)
        var sender = keys.phoneChannel
        var receiver = keys.tvChannel
        let first = try sender.seal(Data("first".utf8))
        let second = try sender.seal(Data("second".utf8))

        var altered = first
        altered[altered.startIndex] ^= 1
        XCTAssertThrowsError(try receiver.open(altered))
        XCTAssertThrowsError(try receiver.open(second), "out of order")
        XCTAssertEqual(try receiver.open(first), Data("first".utf8))
        XCTAssertThrowsError(try receiver.open(first), "replayed")
        XCTAssertEqual(try receiver.open(second), Data("second".utf8))
    }

    func testCodesReadAndPrint() {
        XCTAssertEqual(TVPairingCode("482 913")?.value, 482_913)
        XCTAssertEqual(TVPairingCode("004-213")?.value, 4213)
        XCTAssertNil(TVPairingCode("12345"))
        XCTAssertNil(TVPairingCode("1234567"))
        XCTAssertNil(TVPairingCode("12a456"))
        XCTAssertNil(TVPairingCode("１２３４５６"))
        XCTAssertEqual(TVPairingCode(value: 4213)?.description, "004 213")
        XCTAssertNil(TVPairingCode(value: 1_000_000))
        let random = SystemTVLinkRandom()
        for _ in 0..<200 {
            XCTAssertLessThan(TVPairingCode.random(random).value, 1_000_000)
        }
    }

    func testFramesSurviveArrivingInPieces() throws {
        let one = TVFrame.encode(Data("hello".utf8))
        let two = TVFrame.encode(Data(repeating: 7, count: 70_000))
        var reader = TVFrame.Reader()
        let stream = one + two
        var frames: [Data] = []
        for start in stride(from: 0, to: stream.count, by: 1_000) {
            reader.append(stream[start..<min(start + 1_000, stream.count)])
            while let frame = try reader.next() { frames.append(frame) }
        }
        XCTAssertEqual(frames, [Data("hello".utf8), Data(repeating: 7, count: 70_000)])

        var hostile = TVFrame.Reader()
        hostile.append(Data([0x7F, 0xFF, 0xFF, 0xFF]))
        XCTAssertThrowsError(try hostile.next())
    }
}
