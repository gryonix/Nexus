package com.skaymer.gryonixnexus.app.ai

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.skaymer.gryonixnexus.aiassistant.AIImage
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Base64
import java.util.UUID

/** AI chat pictures stored as JPEG files */
class AiImageStore(private val directory: File) {
    private fun file(id: String) = File(directory, "$id.jpg")

    /** Saves the JPEG and returns its id */
    fun save(jpeg: ByteArray): String? = runCatching {
        directory.mkdirs()
        val id = UUID.randomUUID().toString()
        file(id).writeBytes(jpeg)
        id
    }.getOrNull()

    fun bytes(id: String): ByteArray? = file(id).takeIf { it.exists() }?.readBytes()

    fun delete(ids: List<String>) = ids.forEach { file(it).delete() }

    /** The pictures of one message, ready for the request */
    fun wire(ids: List<String>?): List<AIImage> = ids.orEmpty().mapNotNull { bytes(it) }
        .map { AIImage("image/jpeg", Base64.getEncoder().encodeToString(it)) }

    companion object {
        const val MAX_SIDE = 1568

        /** Any picture bytes as a JPEG no larger than MAX_SIDE */
        fun jpeg(raw: ByteArray): ByteArray? {
            val bitmap = BitmapFactory.decodeByteArray(raw, 0, raw.size) ?: return null
            val scale = minOf(1f, MAX_SIDE.toFloat() / maxOf(bitmap.width, bitmap.height))
            val sized = if (scale < 1f) {
                Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true)
            } else bitmap
            return ByteArrayOutputStream().use { out ->
                sized.compress(Bitmap.CompressFormat.JPEG, 80, out)
                out.toByteArray()
            }
        }
    }
}
