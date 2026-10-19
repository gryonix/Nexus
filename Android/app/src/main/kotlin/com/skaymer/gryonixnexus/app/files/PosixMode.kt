package com.skaymer.gryonixnexus.app.files

import com.skaymer.gryonixnexus.servercontrol.RemoteFileEntry

object PosixMode {
    fun format(permissions: Int?): String? {
        if (permissions == null) return null
        val type = when (RemoteFileEntry.kind(permissions)) {
            RemoteFileEntry.Kind.DIRECTORY -> 'd'
            RemoteFileEntry.Kind.SYMLINK -> 'l'
            RemoteFileEntry.Kind.FILE -> '-'
            RemoteFileEntry.Kind.OTHER -> '?'
        }
        val builder = StringBuilder(10).append(type)
        for (shift in intArrayOf(6, 3, 0)) {
            builder.append(if (permissions shr (shift + 2) and 1 == 1) 'r' else '-')
            builder.append(if (permissions shr (shift + 1) and 1 == 1) 'w' else '-')
            builder.append(execute(permissions, shift))
        }
        return builder.toString()
    }

    private fun execute(permissions: Int, shift: Int): Char {
        val executable = permissions shr shift and 1 == 1
        // 0o4000 setuid, 0o2000 setgid, 0o1000 sticky.
        val special = when (shift) {
            6 -> permissions and 0x800 != 0
            3 -> permissions and 0x400 != 0
            else -> permissions and 0x200 != 0
        }
        val letter = if (shift == 0) 't' else 's'
        return when {
            special && executable -> letter
            special -> letter.uppercaseChar()
            executable -> 'x'
            else -> '-'
        }
    }
}
