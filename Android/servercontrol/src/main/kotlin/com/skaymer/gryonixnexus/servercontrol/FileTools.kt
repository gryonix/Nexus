package com.skaymer.gryonixnexus.servercontrol

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext

data class RemoteBreadcrumb(val name: String, val path: String)

object FileTools {
    /** Root first, then each folder down to the path */
    fun breadcrumbs(path: String): List<RemoteBreadcrumb> {
        val crumbs = mutableListOf(RemoteBreadcrumb("/", "/"))
        var current = "/"
        for (part in path.split('/').filter { it.isNotEmpty() }) {
            current = RemotePath.join(current, part)
            crumbs += RemoteBreadcrumb(part, current)
        }
        return crumbs
    }

    fun isValidName(name: String): Boolean =
        name.isNotEmpty() && name != "." && name != ".." && '/' !in name && '\u0000' !in name
}

enum class PreviewKind { IMAGE, TEXT, NONE }

object FilePreview {
    const val THUMBNAIL_LIMIT: Long = 2L * 1024 * 1024
    private val images = setOf("png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tiff")
    private val texts = setOf(
        "txt", "md", "log", "conf", "cfg", "ini", "json", "yml", "yaml", "toml", "xml", "csv",
        "sh", "env", "service", "py", "rs", "swift", "kt", "js", "html", "css", "sql", "list", "pem",
    )

    fun kind(entry: RemoteFileEntry): PreviewKind {
        if (entry.kind != RemoteFileEntry.Kind.FILE && entry.kind != RemoteFileEntry.Kind.SYMLINK) {
            return PreviewKind.NONE
        }
        val extension = entry.name.substringAfterLast('.', "").lowercase()
        return when {
            extension in images -> PreviewKind.IMAGE
            extension in texts || (extension.isEmpty() && entry.name.startsWith(".")) -> PreviewKind.TEXT
            else -> PreviewKind.NONE
        }
    }

    fun canThumbnail(entry: RemoteFileEntry): Boolean =
        kind(entry) == PreviewKind.IMAGE && (entry.size ?: 0) <= THUMBNAIL_LIMIT
}

object BatchRename {
    data class Change(val oldName: String, val newName: String)

    /** Names that change, left out when invalid or clashing */
    fun plan(names: List<String>, existing: Set<String>, find: String, replace: String): List<Change> {
        if (find.isEmpty()) return emptyList()
        val taken = existing.toMutableSet()
        val changes = mutableListOf<Change>()
        for (name in names) {
            val renamed = name.replace(find, replace)
            if (renamed == name || !FileTools.isValidName(renamed) || renamed in taken) continue
            taken.remove(name)
            taken.add(renamed)
            changes += Change(name, renamed)
        }
        return changes
    }
}

object FileSearch {
    const val DEFAULT_LIMIT = 500
    private const val DIRECTORY_BUDGET = 4000

    fun matches(name: String, pattern: String): Boolean {
        val needle = pattern.trim()
        if (needle.isEmpty()) return false
        if ('*' !in needle && '?' !in needle) return name.contains(needle, ignoreCase = true)
        val regex = needle.map {
            when (it) {
                '*' -> ".*"
                '?' -> "."
                else -> Regex.escape(it.toString())
            }
        }.joinToString("")
        return Regex("^$regex$", RegexOption.IGNORE_CASE).matches(name)
    }

    /** Breadth-first by name; stops at the limit or on cancellation */
    suspend fun walk(
        root: String,
        pattern: String,
        limit: Int,
        list: suspend (String) -> List<RemoteFileEntry>,
    ): List<RemoteFileEntry> {
        val found = mutableListOf<RemoteFileEntry>()
        val queue = ArrayDeque(listOf(root))
        var visited = 0
        while (queue.isNotEmpty() && found.size < limit && visited < DIRECTORY_BUDGET) {
            coroutineContext.ensureActive()
            val directory = queue.removeFirst()
            visited++
            val entries = try {
                list(directory)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (unreadable: Exception) {
                continue
            }
            for (entry in entries) {
                if (matches(entry.name, pattern)) {
                    found += entry
                    if (found.size >= limit) break
                }
                if (entry.kind == RemoteFileEntry.Kind.DIRECTORY) queue.addLast(entry.path)
            }
        }
        return found
    }
}

data class FileShortcuts(
    val bookmarks: List<String> = emptyList(),
    val recents: List<String> = emptyList(),
) {
    fun isBookmarked(path: String): Boolean = path in bookmarks

    fun toggleBookmark(path: String): FileShortcuts =
        copy(bookmarks = if (path in bookmarks) bookmarks - path else bookmarks + path)

    fun noteOpened(path: String): FileShortcuts =
        copy(recents = (listOf(path) + recents.filter { it != path }).take(RECENT_LIMIT))

    fun renamed(oldPath: String, newPath: String): FileShortcuts = copy(
        bookmarks = bookmarks.map { if (it == oldPath) newPath else it },
        recents = recents.map { if (it == oldPath) newPath else it },
    )

    companion object {
        const val RECENT_LIMIT = 20
    }
}
