package com.skaymer.gryonixnexus.servercontrol

import java.math.BigInteger
import java.security.MessageDigest
import java.util.Base64
import kotlinx.serialization.Serializable

/** The key types the app can generate */
enum class SshKeyKind(val algorithm: String, val bits: Int, val artName: String, val displayName: String) {
    ED25519("ssh-ed25519", 256, "ED25519", "Ed25519"),
    ECDSA_P256("ecdsa-sha2-nistp256", 256, "ECDSA", "ECDSA P-256"),
    RSA_3072("ssh-rsa", 3072, "RSA", "RSA 3072"),
    RSA_4096("ssh-rsa", 4096, "RSA", "RSA 4096"),
}

/** One key the user generated */
@Serializable
data class UserSshKey(
    val id: String,
    val name: String,
    val kind: SshKeyKind,
    val createdAtMillis: Long,
    /** One authorized_keys line */
    val publicKey: String,
    /** Unencrypted openssh-key-v1 PEM */
    val privateKeyPem: String,
) {
    val fingerprint: String get() = SshFingerprint.sha256(publicKey).orEmpty()
    val randomArt: String get() = SshFingerprint.randomArt(publicKey, kind).orEmpty()
}

/** Key material in the pieces OpenSSH encodes */
sealed interface SshKeyMaterial {
    class Ed25519(val seed: ByteArray, val publicKey: ByteArray) : SshKeyMaterial
    class EcdsaP256(val publicPoint: ByteArray, val privateScalar: BigInteger) : SshKeyMaterial
    class Rsa(
        val modulus: BigInteger,
        val exponent: BigInteger,
        val privateExponent: BigInteger,
        val coefficient: BigInteger,
        val prime1: BigInteger,
        val prime2: BigInteger,
    ) : SshKeyMaterial
}

/** SSH wire-format writer */
class SshWireWriter {
    private val out = java.io.ByteArrayOutputStream()

    fun bytes(): ByteArray = out.toByteArray()

    fun uint32(value: Int) = apply { out.write(java.nio.ByteBuffer.allocate(4).putInt(value).array()) }

    fun string(data: ByteArray) = apply { uint32(data.size); out.write(data) }

    fun string(text: String) = string(text.toByteArray(Charsets.UTF_8))

    fun raw(data: ByteArray) = apply { out.write(data) }

    fun mpint(value: BigInteger) = string(value.toByteArray())
}

/** OpenSSH public and private key text */
object OpenSshKeyEncoding {
    fun publicBlob(key: SshKeyMaterial): ByteArray {
        val wire = SshWireWriter()
        when (key) {
            is SshKeyMaterial.Ed25519 -> wire.string("ssh-ed25519").string(key.publicKey)
            is SshKeyMaterial.EcdsaP256 ->
                wire.string("ecdsa-sha2-nistp256").string("nistp256").string(key.publicPoint)
            is SshKeyMaterial.Rsa -> wire.string("ssh-rsa").mpint(key.exponent).mpint(key.modulus)
        }
        return wire.bytes()
    }

    fun publicLine(key: SshKeyMaterial, kind: SshKeyKind, comment: String): String =
        "${kind.algorithm} ${Base64.getEncoder().encodeToString(publicBlob(key))} $comment"

    fun privatePem(key: SshKeyMaterial, comment: String, checkInt: Int = java.security.SecureRandom().nextInt()): String {
        val file = SshWireWriter()
            .raw("openssh-key-v1\u0000".toByteArray())
            .string("none").string("none").string(ByteArray(0))
            .uint32(1)
            .string(publicBlob(key))
            .string(privateSection(key, comment, checkInt))
        return wrap(Base64.getEncoder().encodeToString(file.bytes()))
    }

    private fun privateSection(key: SshKeyMaterial, comment: String, checkInt: Int): ByteArray {
        val section = SshWireWriter().uint32(checkInt).uint32(checkInt)
        appendPrivateFields(key, section)
        section.string(comment)
        var pad = 1
        while (section.bytes().size % 8 != 0) section.raw(byteArrayOf(pad++.toByte()))
        return section.bytes()
    }

    private fun appendPrivateFields(key: SshKeyMaterial, wire: SshWireWriter) {
        when (key) {
            is SshKeyMaterial.Ed25519 ->
                wire.string("ssh-ed25519").string(key.publicKey).string(key.seed + key.publicKey)
            is SshKeyMaterial.EcdsaP256 -> wire.string("ecdsa-sha2-nistp256").string("nistp256")
                .string(key.publicPoint).mpint(key.privateScalar)
            is SshKeyMaterial.Rsa -> wire.string("ssh-rsa").mpint(key.modulus).mpint(key.exponent)
                .mpint(key.privateExponent).mpint(key.coefficient).mpint(key.prime1).mpint(key.prime2)
        }
    }

    private fun wrap(base64: String): String =
        (listOf("-----BEGIN OPENSSH PRIVATE KEY-----") + base64.chunked(70) +
            "-----END OPENSSH PRIVATE KEY-----").joinToString("\n") + "\n"
}

/** Key fingerprints and OpenSSH randomart */
object SshFingerprint {
    private const val WIDTH = 17
    private const val HEIGHT = 9
    private const val SYMBOLS = " .o+=*BOX@%&#/^SE"

    fun blob(publicKeyLine: String): ByteArray? {
        val parts = publicKeyLine.trim().split(Regex(" +"))
        if (parts.size < 2) return null
        return runCatching { Base64.getDecoder().decode(parts[1]) }.getOrNull()
    }

    private fun digest(publicKeyLine: String): ByteArray? =
        blob(publicKeyLine)?.let { MessageDigest.getInstance("SHA-256").digest(it) }

    /** "SHA256:" and unpadded base64, as ssh-keygen -l prints */
    fun sha256(publicKeyLine: String): String? = digest(publicKeyLine)?.let {
        "SHA256:" + Base64.getEncoder().withoutPadding().encodeToString(it)
    }

    fun randomArt(publicKeyLine: String, kind: SshKeyKind): String? =
        digest(publicKeyLine)?.let { randomArt(it, kind) }

    /** The drunken-bishop walk over a digest */
    fun randomArt(digest: ByteArray, kind: SshKeyKind): String {
        val field = walk(digest)
        val lines = mutableListOf(border("[${kind.artName} ${kind.bits}]"))
        for (y in 0 until HEIGHT) {
            lines += "|" + (0 until WIDTH).joinToString("") { SYMBOLS[field[it][y]].toString() } + "|"
        }
        lines += border("[SHA256]")
        return lines.joinToString("\n")
    }

    private fun walk(digest: ByteArray): Array<IntArray> {
        val field = Array(WIDTH) { IntArray(HEIGHT) }
        var x = WIDTH / 2
        var y = HEIGHT / 2
        for (byte in digest) {
            var input = byte.toInt() and 0xFF
            repeat(4) {
                x = (x + if (input and 1 != 0) 1 else -1).coerceIn(0, WIDTH - 1)
                y = (y + if (input and 2 != 0) 1 else -1).coerceIn(0, HEIGHT - 1)
                if (field[x][y] < SYMBOLS.length - 3) field[x][y]++
                input = input shr 2
            }
        }
        field[WIDTH / 2][HEIGHT / 2] = SYMBOLS.length - 2
        field[x][y] = SYMBOLS.length - 1
        return field
    }

    private fun border(title: String): String {
        val left = (WIDTH - title.length) / 2
        val right = (WIDTH - left - title.length).coerceAtLeast(0)
        return "+" + "-".repeat(left) + title + "-".repeat(right) + "+"
    }
}

/** Adds a public key to a server user's authorized_keys */
object AuthorizedKeysInstall {
    const val ADDED = "gryonix-key-added"
    const val ALREADY_THERE = "gryonix-key-present"

    enum class Outcome { ADDED, ALREADY_THERE, FAILED }

    /** Idempotent append, file mode 0600 */
    fun command(publicKeyLine: String): String? {
        val parts = publicKeyLine.trim().split(Regex(" +"))
        if (parts.size < 2 || !parts[1].all { it.isLetterOrDigit() && it.code < 128 || it in "+/=" }) return null
        val line = ShellQuoting.singleQuoted(parts.joinToString(" "))
        val blob = ShellQuoting.singleQuoted(parts[1])
        val file = "\"\$HOME/.ssh/authorized_keys\""
        return listOf(
            "umask 077",
            "mkdir -p \"\$HOME/.ssh\"",
            "chmod 700 \"\$HOME/.ssh\"",
            "touch $file",
            "chmod 600 $file",
            "if grep -qF -- $blob $file; then echo $ALREADY_THERE; else " +
                "{ [ -z \"\$(tail -c1 $file)\" ] || echo >> $file; } " +
                "&& printf '%s\\n' $line >> $file && echo $ADDED; fi",
        ).joinToString(" && ")
    }

    fun outcome(result: ExecResult): Outcome = when {
        result.exitCode != 0 -> Outcome.FAILED
        ADDED in result.stdout -> Outcome.ADDED
        ALREADY_THERE in result.stdout -> Outcome.ALREADY_THERE
        else -> Outcome.FAILED
    }
}
