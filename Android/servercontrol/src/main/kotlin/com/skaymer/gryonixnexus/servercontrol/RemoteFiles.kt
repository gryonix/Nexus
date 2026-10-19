package com.skaymer.gryonixnexus.servercontrol

import java.time.Instant

data class RemoteFileEntry(
    val name: String,
    val path: String,
    val kind: Kind,
    val size: Long? = null,
    val modified: Instant? = null,
    val permissions: Int? = null,
) {
    enum class Kind { FILE, DIRECTORY, SYMLINK, OTHER }

    val id: String get() = path

    companion object {
        /** POSIX file-type bits (S_IFMT) from the SFTP permissions word */
        fun kind(permissions: Int?): Kind {
            if (permissions == null) return Kind.OTHER
            return when (permissions and 0xF000) {
                0x4000 -> Kind.DIRECTORY
                0xA000 -> Kind.SYMLINK
                0x8000 -> Kind.FILE
                else -> Kind.OTHER
            }
        }

        fun sorted(entries: List<RemoteFileEntry>): List<RemoteFileEntry> =
            entries.sortedWith(
                compareBy<RemoteFileEntry> { it.kind != Kind.DIRECTORY }
                    .thenBy(String.CASE_INSENSITIVE_ORDER) { it.name },
            )
    }
}

object RemotePath {
    fun join(directory: String, name: String): String =
        if (directory == "/") "/$name" else "$directory/$name"

    fun parent(path: String): String {
        if (path == "/") return "/"
        val index = path.lastIndexOf('/')
        if (index < 0) return "/"
        val parent = path.substring(0, index)
        return parent.ifEmpty { "/" }
    }

    fun fileName(name: String): String =
        name.substringAfterLast('/').trim().takeIf { it.isNotEmpty() && it != "." && it != ".." } ?: "upload"

    fun name(path: String): String {
        val index = path.lastIndexOf('/')
        return if (index < 0) path else path.substring(index + 1)
    }
}

/** SFTP file access to a deployment's hosts */
interface RemoteFileBrowser {
    /** The login user's home directory — the browser's landing path */
    suspend fun homeDirectory(host: SSHHostID): String

    suspend fun listDirectory(path: String, host: SSHHostID): List<RemoteFileEntry>

    suspend fun downloadFile(path: String, host: SSHHostID, maxBytes: Long): ByteArray

    suspend fun uploadFile(data: ByteArray, path: String, host: SSHHostID)

    suspend fun deleteFile(entry: RemoteFileEntry, host: SSHHostID)
}
