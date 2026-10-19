package com.skaymer.gryonixnexus.servercontrol

import java.util.Base64

data class AppSSHIdentity(
    val privateKeySeed: ByteArray,
    /** Full authorized_keys line: "ssh-ed25519 <base64> gryonixnexus-app" */
    val publicKeyOpenSSH: String,
) {
    constructor(privateKeySeed: ByteArray, ed25519PublicKey: ByteArray) : this(
        privateKeySeed,
        OpenSSHPublicKey.encode(ed25519PublicKey, OpenSSHPublicKey.DEFAULT_COMMENT),
    )

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is AppSSHIdentity) return false
        return privateKeySeed.contentEquals(other.privateKeySeed) &&
            publicKeyOpenSSH == other.publicKeyOpenSSH
    }

    override fun hashCode(): Int =
        31 * privateKeySeed.contentHashCode() + publicKeyOpenSSH.hashCode()
}

object OpenSSHPublicKey {
    const val DEFAULT_COMMENT = "gryonixnexus-app"

    fun encode(ed25519PublicKey: ByteArray, comment: String): String {
        val blob = ArrayList<Byte>()
        appendString("ssh-ed25519".toByteArray(Charsets.UTF_8), blob)
        appendString(ed25519PublicKey, blob)
        val base64 = Base64.getEncoder().encodeToString(blob.toByteArray())
        return "ssh-ed25519 $base64 $comment"
    }

    private fun appendString(data: ByteArray, blob: MutableList<Byte>) {
        val length = data.size
        blob += (length ushr 24 and 0xFF).toByte()
        blob += (length ushr 16 and 0xFF).toByte()
        blob += (length ushr 8 and 0xFF).toByte()
        blob += (length and 0xFF).toByte()
        for (byte in data) blob += byte
    }
}

interface SSHIdentityStore {
    fun load(): AppSSHIdentity?
    fun save(identity: AppSSHIdentity)
    fun delete()
}

fun SSHIdentityStore.loadOrGenerate(generate: () -> AppSSHIdentity): AppSSHIdentity {
    load()?.let { return it }
    val fresh = generate()
    save(fresh)
    return fresh
}
