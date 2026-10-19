package com.skaymer.gryonixnexus.servercontrol

/** One backup file from an `ls -lht` listing */
data class BackupEntry(
    val name: String,
    /** Human size as printed by ls -h, e.g */
    val sizeText: String,
    /** Modification date columns as printed by ls, e.g */
    val dateText: String,
    /** mailcow stores each backup as a DIRECTORY */
    val isDirectory: Boolean = false,
    /** The USB drive holding this copy, if any */
    val drive: String? = null,
    /** Exact size and time, when the source reports them */
    val sizeBytes: Long? = null,
    val modifiedAtMillis: Long? = null,
) {
    /** Name without the directory part — what lists and pickers show */
    val displayName: String get() = name.substringAfterLast('/')
}
