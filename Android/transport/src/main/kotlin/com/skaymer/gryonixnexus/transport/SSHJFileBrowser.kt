package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.servercontrol.RemoteFileBrowser
import com.skaymer.gryonixnexus.servercontrol.RemoteFileEntry
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import java.io.ByteArrayOutputStream
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import net.schmizz.sshj.sftp.SFTPClient
import net.schmizz.sshj.xfer.InMemoryDestFile
import net.schmizz.sshj.xfer.InMemorySourceFile

/** SFTP over the session the app already keeps */
class SSHJFileBrowser(private val runner: SSHJCommandRunner) : RemoteFileBrowser {
    override suspend fun homeDirectory(host: SSHHostID): String = withSFTP(host) { sftp ->
        sftp.canonicalize(".")
    }

    override suspend fun listDirectory(path: String, host: SSHHostID): List<RemoteFileEntry> =
        withSFTP(host) { sftp ->
            sftp.ls(path).map { resource ->
                val attrs = resource.attributes
                RemoteFileEntry(
                    name = resource.name,
                    path = resource.path,
                    kind = RemoteFileEntry.kind(attrs.mode.mask),
                    size = attrs.size,
                    modified = Instant.ofEpochSecond(attrs.mtime),
                    permissions = attrs.mode.mask,
                )
            }
        }

    override suspend fun downloadFile(path: String, host: SSHHostID, maxBytes: Long): ByteArray =
        withSFTP(host) { sftp ->
            val size = sftp.stat(path).size
            if (size > maxBytes) {
                throw ServerControlError.FileTooLarge(path, size, maxBytes)
            }
            val sink = ByteArrayOutputStream(size.coerceAtMost(maxBytes).toInt())
            sftp.get(path, object : InMemoryDestFile() {
                override fun getOutputStream() = sink
                override fun getOutputStream(append: Boolean) = sink
                override fun getLength(): Long = sink.size().toLong()
            })
            sink.toByteArray()
        }

    override suspend fun uploadFile(data: ByteArray, path: String, host: SSHHostID) {
        withSFTP(host) { sftp ->
            sftp.put(object : InMemorySourceFile() {
                override fun getName(): String = path.substringAfterLast('/')
                override fun getLength(): Long = data.size.toLong()
                override fun getInputStream() = data.inputStream()
            }, path)
        }
    }

    override suspend fun deleteFile(entry: RemoteFileEntry, host: SSHHostID) {
        withSFTP(host) { sftp ->
            if (entry.kind == RemoteFileEntry.Kind.DIRECTORY) {
                sftp.rmdir(entry.path)
            } else {
                sftp.rm(entry.path)
            }
        }
    }

    private suspend fun <T> withSFTP(host: SSHHostID, body: (SFTPClient) -> T): T =
        withContext(Dispatchers.IO) {
            val client = runner.sshClient(host)
            val sftp = client.newSFTPClient()
            try {
                body(sftp)
            } finally {
                runCatching { sftp.close() }
            }
        }
}
