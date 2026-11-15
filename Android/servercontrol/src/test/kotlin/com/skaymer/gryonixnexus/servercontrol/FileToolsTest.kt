package com.skaymer.gryonixnexus.servercontrol

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class FileToolsTest {
    private fun file(name: String, parent: String, size: Long? = null) =
        RemoteFileEntry(name, RemotePath.join(parent, name), RemoteFileEntry.Kind.FILE, size)

    private fun dir(name: String, parent: String) =
        RemoteFileEntry(name, RemotePath.join(parent, name), RemoteFileEntry.Kind.DIRECTORY)

    @Test
    fun `breadcrumbs walk from the root`() {
        val crumbs = FileTools.breadcrumbs("/home/user/docs")
        assertEquals(listOf("/", "home", "user", "docs"), crumbs.map { it.name })
        assertEquals(listOf("/", "/home", "/home/user", "/home/user/docs"), crumbs.map { it.path })
        assertEquals(1, FileTools.breadcrumbs("/").size)
    }

    @Test
    fun `batch rename skips clashes and unchanged names`() {
        val plan = BatchRename.plan(
            listOf("a_old.txt", "b.txt", "c_old.txt"),
            setOf("a_old.txt", "b.txt", "c_old.txt", "c_new.txt"),
            "_old", "_new",
        )
        assertEquals(listOf("a_new.txt"), plan.map { it.newName })
        assertTrue(BatchRename.plan(listOf("a"), setOf("a"), "a", "x/y").isEmpty())
        assertTrue(BatchRename.plan(listOf("a"), setOf("a"), "", "x").isEmpty())
    }

    @Test
    fun `search matches substrings and wildcards`() {
        assertTrue(FileSearch.matches("Report.PDF", "report"))
        assertTrue(FileSearch.matches("report.pdf", "*.pdf"))
        assertFalse(FileSearch.matches("report.txt", "*.pdf"))
        assertFalse(FileSearch.matches("x", "  "))
    }

    @Test
    fun `the walk is recursive and limited`() = runTest {
        val tree = mapOf(
            "/" to listOf(dir("a", "/"), file("hit1.txt", "/")),
            "/a" to listOf(file("hit2.txt", "/a"), dir("b", "/a")),
            "/a/b" to listOf(file("hit3.txt", "/a/b")),
        )
        val all = FileSearch.walk("/", "hit", 10) { tree[it].orEmpty() }
        assertEquals(listOf("hit1.txt", "hit2.txt", "hit3.txt"), all.map { it.name }.sorted())
        assertEquals(2, FileSearch.walk("/", "hit", 2) { tree[it].orEmpty() }.size)
    }

    @Test
    fun `a cancelled walk stops`() = runTest {
        val job = kotlinx.coroutines.CompletableDeferred<Unit>()
        job.cancel()
        val outcome = runCatching {
            kotlinx.coroutines.withContext(job) { FileSearch.walk("/", "x", 5) { emptyList() } }
        }
        assertTrue(outcome.exceptionOrNull() is CancellationException)
    }

    @Test
    fun `previews and thumbnails follow the extension and size`() {
        assertEquals(PreviewKind.IMAGE, FilePreview.kind(file("a.PNG", "/", 10)))
        assertEquals(PreviewKind.TEXT, FilePreview.kind(file("notes.md", "/")))
        assertEquals(PreviewKind.NONE, FilePreview.kind(file("blob.bin", "/")))
        assertTrue(FilePreview.canThumbnail(file("a.jpg", "/", 2L * 1024 * 1024)))
        assertFalse(FilePreview.canThumbnail(file("a.jpg", "/", 2L * 1024 * 1024 + 1)))
    }

    @Test
    fun `shortcuts keep twenty recents and toggle bookmarks`() {
        var shortcuts = FileShortcuts()
        for (index in 0 until 25) shortcuts = shortcuts.noteOpened("/f$index")
        assertEquals(20, shortcuts.recents.size)
        assertEquals("/f24", shortcuts.recents.first())
        shortcuts = shortcuts.noteOpened("/f10")
        assertEquals("/f10", shortcuts.recents.first())
        assertEquals(1, shortcuts.recents.count { it == "/f10" })
        shortcuts = shortcuts.toggleBookmark("/x").renamed("/x", "/y")
        assertTrue(shortcuts.isBookmarked("/y"))
        assertTrue(shortcuts.toggleBookmark("/y").bookmarks.isEmpty())
    }
}
