package com.skaymer.gryonixnexus.tvlink

import java.io.File
import java.util.Base64
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer

interface TvSecretStoring {
    fun store(secret: String, account: String)
    fun secret(account: String): String?
    fun delete(account: String)
}

@Serializable
data class TvPairedTv(
    val id: String,
    val name: String,
    val address: TvAddress? = null,
    val pairedAt: Long,
    val vouchedAt: Long? = null,
    val sent: List<TvSentServer> = emptyList(),
)

/** Paired TVs in a file, their pairing keys under `tvlink.tv.<id>`. */
class TvPairedTvStore(private val file: File, private val secrets: TvSecretStoring) {
    private val lock = Any()
    private val serializer = ListSerializer(TvPairedTv.serializer())

    fun all(): List<TvPairedTv> = synchronized(lock) { read() }

    fun record(id: String): TvPairedTv? = all().firstOrNull { it.id == id }

    fun save(tv: TvPairedTv, pairingKey: ByteArray? = null) = synchronized(lock) {
        if (pairingKey != null) secrets.store(Base64.getEncoder().encodeToString(pairingKey), account(tv.id))
        write(read().filterNot { it.id == tv.id } + tv)
    }

    fun pairingKey(id: String): ByteArray? =
        secrets.secret(account(id))?.let { runCatching { Base64.getDecoder().decode(it) }.getOrNull() }

    fun remove(id: String) = synchronized(lock) {
        secrets.delete(account(id))
        write(read().filterNot { it.id == id })
    }

    private fun account(id: String) = "tvlink.tv.$id"

    private fun read(): List<TvPairedTv> =
        if (!file.isFile) {
            emptyList()
        } else {
            runCatching { TvJson.decodeFromString(serializer, file.readText()) }.getOrDefault(emptyList())
        }

    private fun write(list: List<TvPairedTv>) {
        file.parentFile?.mkdirs()
        val temp = File(file.parentFile, file.name + ".tmp")
        temp.writeText(TvJson.encodeToString(serializer, list))
        if (!temp.renameTo(file)) {
            file.delete()
            temp.renameTo(file)
        }
    }
}
