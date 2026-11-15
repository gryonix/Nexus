package com.skaymer.gryonixnexus.tvlink

class TvPairingResult(val peer: TvPeer, val pairingKey: ByteArray)

class TvPairingPhone(private val phone: TvPeer, private val random: TvLinkRandom = SystemTvLinkRandom()) {
    sealed interface Step {
        class Send(val message: TvHandshakeMessage) : Step
        /** The TV shows its code; call [enter]. */
        data object NeedsCode : Step
        class SendSealed(val frame: ByteArray) : Step
    }

    private sealed interface State {
        data object AwaitingHello : State
        data object AwaitingCode : State
        data class AwaitingCommit(val round: Int) : State
        data class AwaitingReveal(val round: Int) : State
        data object AwaitingConfirm : State
        data object Done : State
    }

    private val key = random.keyPair()
    private val nonce = random.bytes(TvCrypto.NONCE_LENGTH)
    private var state: State = State.AwaitingHello
    private var code: TvPairingCode = TvPairingCode.of(0)!!
    var tv: TvPeer? = null
        private set
    private var tvKey = ByteArray(0)
    private var tvNonce = ByteArray(0)
    private var ownRoundNonce = ByteArray(0)
    private var tvCommitment = ByteArray(0)
    private var keys: TvHandshakeKeys? = null
    private var channel: TvSecureChannel? = null

    fun hello() = TvHandshakeMessage(
        t = TvHandshakeMessage.HELLO, v = TvLinkService.PROTOCOL_VERSION, mode = "pair",
        id = phone.id, name = phone.name, key = key.publicX963.b64(), nonce = nonce.b64(),
    )

    fun receive(message: TvHandshakeMessage): Step {
        if (message.t == TvHandshakeMessage.ERROR) throw TvLinkException.Refused(TvRefusal.of(message.code))
        val current = state
        return when {
            current == State.AwaitingHello && message.t == TvHandshakeMessage.HELLO -> {
                if (message.v != TvLinkService.PROTOCOL_VERSION) throw TvLinkException.Refused(TvRefusal.VERSION)
                val id = message.id ?: throw TvLinkException.Unexpected("hello without id")
                val peerKey = message.key?.unb64() ?: throw TvLinkException.Unexpected("hello without key")
                val peerNonce = message.nonce?.unb64() ?: throw TvLinkException.Unexpected("hello without nonce")
                if (peerNonce.size != TvCrypto.NONCE_LENGTH) throw TvLinkException.Unexpected("nonce")
                TvCrypto.publicKey(peerKey)
                tv = TvPeer(id, message.name.orEmpty())
                tvKey = peerKey
                tvNonce = peerNonce
                state = State.AwaitingCode
                Step.NeedsCode
            }
            current is State.AwaitingCommit && message.t == TvHandshakeMessage.COMMIT -> {
                val value = message.value?.unb64()
                if (message.round != current.round || value == null) throw TvLinkException.Unexpected("commit")
                tvCommitment = value
                state = State.AwaitingReveal(current.round)
                Step.Send(TvHandshakeMessage(t = TvHandshakeMessage.REVEAL, round = current.round, value = ownRoundNonce.b64()))
            }
            current is State.AwaitingReveal && message.t == TvHandshakeMessage.REVEAL -> {
                val value = message.value?.unb64()
                if (message.round != current.round || value == null) throw TvLinkException.Unexpected("reveal")
                val expected = TvCrypto.commitment(current.round, code.bit(current.round), tvKey, key.publicX963, value)
                if (!TvCrypto.constantTimeEquals(expected, tvCommitment)) throw TvLinkException.CodeMismatch()
                if (current.round + 1 < TvPairingCode.BIT_COUNT) {
                    Step.Send(commit(current.round + 1))
                } else {
                    val finished = finish()
                    val sealing = finished.phoneChannel
                    val sealed = sealing.seal(TvMessage(t = TvMessage.PAIRED))
                    keys = finished
                    channel = sealing
                    state = State.AwaitingConfirm
                    Step.SendSealed(sealed)
                }
            }
            else -> throw TvLinkException.Unexpected("${message.t} in $current")
        }
    }

    /** The code read off the TV: the first round's commitment. */
    fun enter(code: TvPairingCode): TvHandshakeMessage {
        if (state != State.AwaitingCode) throw TvLinkException.Unexpected("code not asked for")
        this.code = code
        return commit(0)
    }

    fun receiveSealed(frame: ByteArray): TvPairingResult {
        val open = channel
        val peer = tv
        val pairingKey = keys?.pairingKey
        if (state != State.AwaitingConfirm || open == null || peer == null || pairingKey == null) {
            throw TvLinkException.Unexpected("sealed frame")
        }
        if (open.openMessage(frame).t != TvMessage.PAIRED) throw TvLinkException.Unexpected("confirmation")
        state = State.Done
        return TvPairingResult(peer, pairingKey)
    }

    private fun commit(round: Int): TvHandshakeMessage {
        ownRoundNonce = random.bytes(TvCrypto.COMMIT_NONCE_LENGTH)
        state = State.AwaitingCommit(round)
        val value = TvCrypto.commitment(round, code.bit(round), key.publicX963, tvKey, ownRoundNonce)
        return TvHandshakeMessage(t = TvHandshakeMessage.COMMIT, round = round, value = value.b64())
    }

    private fun finish(): TvHandshakeKeys {
        val peer = tv ?: throw TvLinkException.Unexpected("no TV")
        val shared = TvCrypto.sharedSecret(key.private, tvKey)
        val transcript = TvTranscript().apply {
            append("pair"); append(phone.id); append(phone.name); append(peer.id); append(peer.name)
            append(key.publicX963); append(tvKey); append(nonce); append(tvNonce)
        }.hash
        return TvHandshakeKeys.derive(shared, transcript, pairing = true)
    }
}

class TvSessionPhone(
    private val phone: TvPeer,
    private val tvId: String,
    private val pairingKey: ByteArray,
    random: TvLinkRandom = SystemTvLinkRandom(),
) {
    private val key = random.keyPair()
    private val nonce = random.bytes(TvCrypto.NONCE_LENGTH)

    fun hello() = TvHandshakeMessage(
        t = TvHandshakeMessage.HELLO, v = TvLinkService.PROTOCOL_VERSION, mode = "session",
        id = phone.id, name = phone.name, key = key.publicX963.b64(), nonce = nonce.b64(),
    )

    fun receive(message: TvHandshakeMessage): TvSecureChannel {
        if (message.t == TvHandshakeMessage.ERROR) throw TvLinkException.Refused(TvRefusal.of(message.code))
        if (message.t != TvHandshakeMessage.HELLO) throw TvLinkException.Unexpected(message.t)
        if (message.v != TvLinkService.PROTOCOL_VERSION) throw TvLinkException.Refused(TvRefusal.VERSION)
        if (message.id != tvId) throw TvLinkException.WrongPeer()
        val tvKey = message.key?.unb64() ?: throw TvLinkException.Unexpected("hello without key")
        val tvNonce = message.nonce?.unb64() ?: throw TvLinkException.Unexpected("hello without nonce")
        if (tvNonce.size != TvCrypto.NONCE_LENGTH) throw TvLinkException.Unexpected("nonce")
        val shared = TvCrypto.sharedSecret(key.private, tvKey)
        val transcript = TvTranscript().apply {
            append("session"); append(phone.id); append(tvId)
            append(key.publicX963); append(tvKey); append(nonce); append(tvNonce)
        }.hash
        return TvHandshakeKeys.derive(pairingKey + shared, transcript, pairing = false).phoneChannel
    }
}
