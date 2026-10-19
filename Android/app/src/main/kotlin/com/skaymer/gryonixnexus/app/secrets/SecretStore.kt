package com.skaymer.gryonixnexus.app.secrets

import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

interface SecretStore {
    fun secret(account: String): ByteArray?
    fun setSecret(account: String, value: ByteArray)
    fun deleteSecret(account: String)

    fun string(account: String): String? = secret(account)?.toString(Charsets.UTF_8)
    fun setString(account: String, value: String) = setSecret(account, value.toByteArray())
}

class KeystoreSecretStore(private val prefs: SharedPreferences) : SecretStore {
    override fun secret(account: String): ByteArray? {
        val stored = prefs.getString(account, null) ?: return null
        val envelope = Base64.decode(stored, Base64.NO_WRAP)
        if (envelope.size <= IV_BYTES) return null
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            key(),
            GCMParameterSpec(TAG_BITS, envelope, 0, IV_BYTES)
        )
        return cipher.doFinal(envelope, IV_BYTES, envelope.size - IV_BYTES)
    }

    override fun setSecret(account: String, value: ByteArray) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val ciphertext = cipher.doFinal(value)
        val envelope = cipher.iv + ciphertext
        prefs.edit().putString(account, Base64.encodeToString(envelope, Base64.NO_WRAP)).apply()
    }

    override fun deleteSecret(account: String) {
        prefs.edit().remove(account).apply()
    }

    private fun key(): SecretKey = synchronized(KEY_LOCK) {
        val keystore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keystore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return@synchronized it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        generator.generateKey()
    }

    private companion object {
        val KEY_LOCK = Any()
        const val KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "gryonixnexus.secrets"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
        const val TAG_BITS = 128
    }
}
