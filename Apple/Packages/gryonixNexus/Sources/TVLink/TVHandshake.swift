import CryptoKit
import Foundation

/// Who is on one end of the link
public struct TVPeer: Codable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum TVHandshakeError: Error, Equatable {
    /// The peer refused, and said why
    case refused(TVHandshakeMessage.Refusal)
    case codeMismatch
    case unexpected
    case wrongPeer
}

public struct TVPairingResult: Equatable, Sendable {
    public let peer: TVPeer
    public let pairingKey: Data

    public init(peer: TVPeer, pairingKey: Data) {
        self.peer = peer
        self.pairingKey = pairingKey
    }
}

public struct TVPairingPhone: Sendable {
    public enum Step: Sendable {
        case send(TVHandshakeMessage)
        /// The TV answered and shows its code; call `enter(_:)`
        case needsCode
        /// The handshake is over; this sealed frame confirms it
        case sendSealed(Data)
    }

    private enum State: Sendable {
        case awaitingHello, awaitingCode, awaitingCommit(Int), awaitingReveal(Int), awaitingConfirm, done
    }

    private let phone: TVPeer
    private var code = TVPairingCode(value: 0)!
    private let random: TVLinkRandom
    private let key: P256.KeyAgreement.PrivateKey
    private let nonce: Data
    private var state = State.awaitingHello
    private var tv: TVPeer?
    private var tvKey = Data()
    private var tvNonce = Data()
    private var ownRoundNonce = Data()
    private var tvCommitment = Data()
    private var keys: TVHandshakeKeys?
    private var channel: TVSecureChannel?

    public init(phone: TVPeer, random: TVLinkRandom = SystemTVLinkRandom()) {
        self.phone = phone
        self.random = random
        self.key = random.keyAgreementKey()
        self.nonce = random.bytes(TVLinkCrypto.nonceLength)
    }

    private var ownKey: Data { key.publicKey.x963Representation }

    /// The TV that answered, once it has
    public var tvPeer: TVPeer? { tv }

    public func hello() -> TVHandshakeMessage {
        TVHandshakeMessage(t: .hello, v: TVLinkService.protocolVersion, mode: .pair, id: phone.id,
                           name: phone.name, key: ownKey, nonce: nonce)
    }

    public mutating func receive(_ message: TVHandshakeMessage) throws -> Step {
        if message.t == .error { throw TVHandshakeError.refused(message.code ?? .protocolError) }
        switch (state, message.t) {
        case (.awaitingHello, .hello):
            guard message.v == TVLinkService.protocolVersion else { throw TVHandshakeError.refused(.version) }
            guard let id = message.id, let key = message.key, let nonce = message.nonce,
                  nonce.count == TVLinkCrypto.nonceLength,
                  (try? P256.KeyAgreement.PublicKey(x963Representation: key)) != nil
            else { throw TVHandshakeError.unexpected }
            tv = TVPeer(id: id, name: message.name ?? "")
            tvKey = key
            tvNonce = nonce
            state = .awaitingCode
            return .needsCode
        case (.awaitingCommit(let round), .commit):
            guard message.round == round, let value = message.value else { throw TVHandshakeError.unexpected }
            tvCommitment = value
            state = .awaitingReveal(round)
            return .send(TVHandshakeMessage(t: .reveal, round: round, value: ownRoundNonce))
        case (.awaitingReveal(let round), .reveal):
            guard message.round == round, let value = message.value else { throw TVHandshakeError.unexpected }
            let expected = TVLinkCrypto.commitment(round: round, bit: code.bit(round), ownKey: tvKey,
                                                   peerKey: ownKey, nonce: value)
            guard constantTimeEqual(expected, tvCommitment) else { throw TVHandshakeError.codeMismatch }
            if round + 1 < TVPairingCode.bitCount { return .send(commit(round: round + 1)) }
            let keys = try finish()
            var channel = keys.phoneChannel
            let sealed = try channel.seal(TVMessage(t: .paired))
            self.keys = keys
            self.channel = channel
            state = .awaitingConfirm
            return .sendSealed(sealed)
        default:
            throw TVHandshakeError.unexpected
        }
    }

    public mutating func enter(_ code: TVPairingCode) throws -> TVHandshakeMessage {
        guard case .awaitingCode = state else { throw TVHandshakeError.unexpected }
        self.code = code
        return commit(round: 0)
    }

    /// The TV's sealed confirmation; pairing is done when this returns
    public mutating func receiveSealed(_ frame: Data) throws -> TVPairingResult {
        guard case .awaitingConfirm = state, var channel, let tv,
              let pairingKey = keys?.pairingKey else { throw TVHandshakeError.unexpected }
        let message = try channel.openMessage(frame)
        guard message.t == .paired else { throw TVHandshakeError.unexpected }
        state = .done
        return TVPairingResult(peer: tv, pairingKey: pairingKey)
    }

    private mutating func commit(round: Int) -> TVHandshakeMessage {
        ownRoundNonce = random.bytes(TVLinkCrypto.commitNonceLength)
        state = .awaitingCommit(round)
        let value = TVLinkCrypto.commitment(round: round, bit: code.bit(round), ownKey: ownKey,
                                            peerKey: tvKey, nonce: ownRoundNonce)
        return TVHandshakeMessage(t: .commit, round: round, value: value)
    }

    private func finish() throws -> TVHandshakeKeys {
        let shared = try TVLinkCrypto.sharedSecret(key, peer: tvKey)
        let transcript = TVHandshakeTranscript.pairing(phone: phone, tv: tv ?? TVPeer(id: "", name: ""),
                                                       phoneKey: ownKey, tvKey: tvKey,
                                                       phoneNonce: nonce, tvNonce: tvNonce)
        return TVHandshakeKeys.derive(material: shared, transcript: transcript, pairing: true)
    }
}

/// The TV's side: it drew the code and shows it
public struct TVPairingTV: Sendable {
    public enum Step: Sendable {
        case send(TVHandshakeMessage)
        /// The handshake is over: send this and remember the phone
        case finished(sealed: Data, TVPairingResult)
    }

    private enum State: Sendable {
        case awaitingHello, awaitingCommit(Int), awaitingReveal(Int), awaitingConfirm, done
    }

    private let tv: TVPeer
    private let code: TVPairingCode
    private let random: TVLinkRandom
    private let key: P256.KeyAgreement.PrivateKey
    private let nonce: Data
    private var state = State.awaitingHello
    private var phone: TVPeer?
    private var phoneKey = Data()
    private var phoneNonce = Data()
    private var phoneCommitment = Data()
    private var ownRoundNonce = Data()
    private var keys: TVHandshakeKeys?

    public init(tv: TVPeer, code: TVPairingCode, random: TVLinkRandom = SystemTVLinkRandom()) {
        self.tv = tv
        self.code = code
        self.random = random
        self.key = random.keyAgreementKey()
        self.nonce = random.bytes(TVLinkCrypto.nonceLength)
    }

    private var ownKey: Data { key.publicKey.x963Representation }

    public var phonePeer: TVPeer? { phone }

    public mutating func receive(_ message: TVHandshakeMessage) throws -> TVHandshakeMessage {
        switch (state, message.t) {
        case (.awaitingHello, .hello):
            guard message.v == TVLinkService.protocolVersion else { throw TVHandshakeError.refused(.version) }
            guard message.mode == .pair, let id = message.id, let key = message.key,
                  let nonce = message.nonce, nonce.count == TVLinkCrypto.nonceLength,
                  (try? P256.KeyAgreement.PublicKey(x963Representation: key)) != nil
            else { throw TVHandshakeError.unexpected }
            phone = TVPeer(id: id, name: message.name ?? "")
            phoneKey = key
            phoneNonce = nonce
            state = .awaitingCommit(0)
            return TVHandshakeMessage(t: .hello, v: TVLinkService.protocolVersion, mode: .pair, id: tv.id,
                                      name: tv.name, key: ownKey, nonce: self.nonce)
        case (.awaitingCommit(let round), .commit):
            guard message.round == round, let value = message.value else { throw TVHandshakeError.unexpected }
            phoneCommitment = value
            ownRoundNonce = random.bytes(TVLinkCrypto.commitNonceLength)
            state = .awaitingReveal(round)
            let commitment = TVLinkCrypto.commitment(round: round, bit: code.bit(round), ownKey: ownKey,
                                                     peerKey: phoneKey, nonce: ownRoundNonce)
            return TVHandshakeMessage(t: .commit, round: round, value: commitment)
        case (.awaitingReveal(let round), .reveal):
            guard message.round == round, let value = message.value else { throw TVHandshakeError.unexpected }
            let expected = TVLinkCrypto.commitment(round: round, bit: code.bit(round), ownKey: phoneKey,
                                                   peerKey: ownKey, nonce: value)
            guard constantTimeEqual(expected, phoneCommitment) else { throw TVHandshakeError.codeMismatch }
            if round + 1 < TVPairingCode.bitCount {
                state = .awaitingCommit(round + 1)
            } else {
                keys = try finish()
                state = .awaitingConfirm
            }
            return TVHandshakeMessage(t: .reveal, round: round, value: ownRoundNonce)
        default:
            throw TVHandshakeError.unexpected
        }
    }

    public var awaitsSealedConfirmation: Bool {
        if case .awaitingConfirm = state { return true }
        return false
    }

    public mutating func receiveSealed(_ frame: Data) throws -> Step {
        guard case .awaitingConfirm = state, let keys, let pairingKey = keys.pairingKey,
              let phone else { throw TVHandshakeError.unexpected }
        var channel = keys.tvChannel
        let message = try channel.openMessage(frame)
        guard message.t == .paired else { throw TVHandshakeError.unexpected }
        state = .done
        return .finished(sealed: try channel.seal(TVMessage(t: .paired)),
                         TVPairingResult(peer: phone, pairingKey: pairingKey))
    }

    private func finish() throws -> TVHandshakeKeys {
        let shared = try TVLinkCrypto.sharedSecret(key, peer: phoneKey)
        let transcript = TVHandshakeTranscript.pairing(phone: phone ?? TVPeer(id: "", name: ""), tv: tv,
                                                       phoneKey: phoneKey, tvKey: ownKey,
                                                       phoneNonce: phoneNonce, tvNonce: nonce)
        return TVHandshakeKeys.derive(material: shared, transcript: transcript, pairing: true)
    }
}

public struct TVSessionPhone: Sendable {
    private let phone: TVPeer
    private let tvID: String
    private let pairingKey: Data
    private let key: P256.KeyAgreement.PrivateKey
    private let nonce: Data

    public init(phone: TVPeer, tvID: String, pairingKey: Data, random: TVLinkRandom = SystemTVLinkRandom()) {
        self.phone = phone
        self.tvID = tvID
        self.pairingKey = pairingKey
        self.key = random.keyAgreementKey()
        self.nonce = random.bytes(TVLinkCrypto.nonceLength)
    }

    public func hello() -> TVHandshakeMessage {
        TVHandshakeMessage(t: .hello, v: TVLinkService.protocolVersion, mode: .session, id: phone.id,
                           name: phone.name, key: key.publicKey.x963Representation, nonce: nonce)
    }

    /// The TV's hello turns into the session's channel
    public func receive(_ message: TVHandshakeMessage) throws -> TVSecureChannel {
        if message.t == .error { throw TVHandshakeError.refused(message.code ?? .protocolError) }
        guard message.t == .hello else { throw TVHandshakeError.unexpected }
        guard message.v == TVLinkService.protocolVersion else { throw TVHandshakeError.refused(.version) }
        guard message.id == tvID else { throw TVHandshakeError.wrongPeer }
        guard let tvKey = message.key, let tvNonce = message.nonce,
              tvNonce.count == TVLinkCrypto.nonceLength else { throw TVHandshakeError.unexpected }
        let shared = try TVLinkCrypto.sharedSecret(key, peer: tvKey)
        let transcript = TVHandshakeTranscript.session(phoneID: phone.id, tvID: tvID,
                                                       phoneKey: key.publicKey.x963Representation,
                                                       tvKey: tvKey, phoneNonce: nonce, tvNonce: tvNonce)
        return TVHandshakeKeys.derive(material: pairingKey + shared, transcript: transcript,
                                      pairing: false).phoneChannel
    }
}

/// The TV answering a session hello
public struct TVSessionTV: Sendable {
    public struct Accepted: Sendable {
        public let reply: TVHandshakeMessage
        public let channel: TVSecureChannel
        public let phoneID: String
    }

    private let tv: TVPeer
    private let key: P256.KeyAgreement.PrivateKey
    private let nonce: Data

    public init(tv: TVPeer, random: TVLinkRandom = SystemTVLinkRandom()) {
        self.tv = tv
        self.key = random.keyAgreementKey()
        self.nonce = random.bytes(TVLinkCrypto.nonceLength)
    }

    public func accept(_ hello: TVHandshakeMessage,
                       pairingKey: (String) -> Data?) throws -> Accepted {
        guard hello.t == .hello, hello.mode == .session else { throw TVHandshakeError.unexpected }
        guard hello.v == TVLinkService.protocolVersion else { throw TVHandshakeError.refused(.version) }
        guard let phoneID = hello.id, let phoneKey = hello.key, let phoneNonce = hello.nonce,
              phoneNonce.count == TVLinkCrypto.nonceLength else { throw TVHandshakeError.unexpected }
        guard let secret = pairingKey(phoneID) else { throw TVHandshakeError.refused(.unknownPhone) }
        let ownKey = key.publicKey.x963Representation
        let shared = try TVLinkCrypto.sharedSecret(key, peer: phoneKey)
        let transcript = TVHandshakeTranscript.session(phoneID: phoneID, tvID: tv.id, phoneKey: phoneKey,
                                                       tvKey: ownKey, phoneNonce: phoneNonce, tvNonce: nonce)
        let keys = TVHandshakeKeys.derive(material: secret + shared, transcript: transcript, pairing: false)
        let reply = TVHandshakeMessage(t: .hello, v: TVLinkService.protocolVersion, mode: .session,
                                       id: tv.id, name: tv.name, key: ownKey, nonce: nonce)
        return Accepted(reply: reply, channel: keys.tvChannel, phoneID: phoneID)
    }
}

enum TVHandshakeTranscript {
    static func pairing(phone: TVPeer, tv: TVPeer, phoneKey: Data, tvKey: Data,
                        phoneNonce: Data, tvNonce: Data) -> Data {
        var transcript = TVTranscript()
        transcript.append("pair")
        transcript.append(phone.id)
        transcript.append(phone.name)
        transcript.append(tv.id)
        transcript.append(tv.name)
        transcript.append(phoneKey)
        transcript.append(tvKey)
        transcript.append(phoneNonce)
        transcript.append(tvNonce)
        return transcript.hash
    }

    static func session(phoneID: String, tvID: String, phoneKey: Data, tvKey: Data,
                        phoneNonce: Data, tvNonce: Data) -> Data {
        var transcript = TVTranscript()
        transcript.append("session")
        transcript.append(phoneID)
        transcript.append(tvID)
        transcript.append(phoneKey)
        transcript.append(tvKey)
        transcript.append(phoneNonce)
        transcript.append(tvNonce)
        return transcript.hash
    }
}

func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
    guard lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
}
