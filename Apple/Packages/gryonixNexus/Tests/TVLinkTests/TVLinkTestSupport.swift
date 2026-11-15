import CryptoKit
import Foundation
@testable import TVLink

final class ScriptedRandom: TVLinkRandom, @unchecked Sendable {
    private let lock = NSLock()
    private var counter: UInt32 = 0
    private let seed: String
    private(set) var handedOut: [Data] = []

    init(seed: String) {
        self.seed = seed
    }

    private func next() -> Data {
        lock.withLock {
            counter += 1
            var input = Data(seed.utf8)
            var big = counter.bigEndian
            input.append(Data(bytes: &big, count: 4))
            return Data(SHA256.hash(data: input))
        }
    }

    func bytes(_ count: Int) -> Data {
        var out = Data()
        while out.count < count { out.append(next()) }
        let value = out.prefix(count)
        lock.withLock { handedOut.append(Data(value)) }
        return Data(value)
    }

    func keyAgreementKey() -> P256.KeyAgreement.PrivateKey {
        while true {
            let scalar = next()
            if let key = try? P256.KeyAgreement.PrivateKey(rawRepresentation: scalar) {
                lock.withLock { handedOut.append(scalar) }
                return key
            }
        }
    }
}

/// Runs a whole pairing in memory, recording every frame
struct PairingRun {
    var frames: [(from: String, payload: Data)] = []
    var phoneResult: TVPairingResult?
    var tvResult: TVPairingResult?
    var failure: Error?

    static func run(phone: TVPeer, tv: TVPeer, typed: TVPairingCode, shown: TVPairingCode,
                    phoneRandom: TVLinkRandom = SystemTVLinkRandom(),
                    tvRandom: TVLinkRandom = SystemTVLinkRandom()) -> PairingRun {
        var run = PairingRun()
        var phoneSide = TVPairingPhone(phone: phone, random: phoneRandom)
        var tvSide = TVPairingTV(tv: tv, code: shown, random: tvRandom)
        do {
            var outgoing = phoneSide.hello()
            run.record("phone", try TVJSON.encode(outgoing))
            var answer = try tvSide.receive(outgoing)
            run.record("tv", try TVJSON.encode(answer))
            guard case .needsCode = try phoneSide.receive(answer) else { throw TVHandshakeError.unexpected }
            outgoing = try phoneSide.enter(typed)
            while true {
                run.record("phone", try TVJSON.encode(outgoing))
                do {
                    answer = try tvSide.receive(outgoing)
                } catch TVHandshakeError.codeMismatch {
                    answer = .refusal(.wrongCode)
                    run.record("tv", try TVJSON.encode(answer))
                    _ = try phoneSide.receive(answer)
                    throw TVHandshakeError.codeMismatch
                }
                run.record("tv", try TVJSON.encode(answer))
                switch try phoneSide.receive(answer) {
                case .send(let next):
                    outgoing = next
                case .sendSealed(let sealed):
                    run.record("phone", sealed)
                    guard case .finished(let reply, let result) = try tvSide.receiveSealed(sealed) else {
                        throw TVHandshakeError.unexpected
                    }
                    run.tvResult = result
                    run.record("tv", reply)
                    run.phoneResult = try phoneSide.receiveSealed(reply)
                    return run
                case .needsCode:
                    throw TVHandshakeError.unexpected
                }
            }
        } catch {
            run.failure = error
            return run
        }
    }

    private mutating func record(_ from: String, _ payload: Data) {
        frames.append((from, payload))
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }

    init?(hex: String) {
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
