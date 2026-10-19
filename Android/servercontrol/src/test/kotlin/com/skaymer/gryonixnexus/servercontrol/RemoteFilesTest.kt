package com.skaymer.gryonixnexus.servercontrol

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class RemoteFilesTest {
    @Test
    fun anUploadNameCannotLeaveItsFolder() {
        assertEquals("authorized_keys", RemotePath.fileName("../../.ssh/authorized_keys"))
        assertEquals("notes.txt", RemotePath.fileName("notes.txt"))
        assertEquals("upload", RemotePath.fileName(".."))
        assertEquals("upload", RemotePath.fileName("a/"))
    }

    @Test
    fun `the POSIX type bits decide the kind`() {
        assertEquals(RemoteFileEntry.Kind.DIRECTORY, RemoteFileEntry.kind(0b100_000_111_101_101))
        assertEquals(RemoteFileEntry.Kind.FILE, RemoteFileEntry.kind(0b1000_000_110_100_100))
        assertEquals(RemoteFileEntry.Kind.SYMLINK, RemoteFileEntry.kind(0b1010_000_111_111_111))
        assertEquals(RemoteFileEntry.Kind.OTHER, RemoteFileEntry.kind(0b110_000_110_110_000))
        assertEquals(RemoteFileEntry.Kind.OTHER, RemoteFileEntry.kind(null))
    }

    @Test
    fun `joining handles the root, which has no separator to add`() {
        assertEquals("/opt", RemotePath.join("/", "opt"))
        assertEquals("/opt/backups", RemotePath.join("/opt", "backups"))
        assertEquals("/home/admin/file.txt", RemotePath.join("/home/admin", "file.txt"))
    }

    @Test
    fun `the parent of the root is the root`() {
        assertEquals("/opt", RemotePath.parent("/opt/backups"))
        assertEquals("/", RemotePath.parent("/opt"))
        assertEquals("/", RemotePath.parent("/"))
    }

    @Test
    fun `the name is the last component`() {
        assertEquals("x.tar.gz", RemotePath.name("/opt/backups/x.tar.gz"))
        assertEquals("opt", RemotePath.name("/opt"))
    }

    @Test
    fun `directories come first, then names case-insensitively`() {
        val entries = listOf(
            RemoteFileEntry("zeta.txt", "/zeta.txt", RemoteFileEntry.Kind.FILE),
            RemoteFileEntry("Alpha", "/Alpha", RemoteFileEntry.Kind.DIRECTORY),
            RemoteFileEntry("beta.log", "/beta.log", RemoteFileEntry.Kind.FILE),
            RemoteFileEntry("backups", "/backups", RemoteFileEntry.Kind.DIRECTORY),
        )
        assertEquals(
            listOf("Alpha", "backups", "beta.log", "zeta.txt"),
            RemoteFileEntry.sorted(entries).map { it.name },
        )
    }
}
