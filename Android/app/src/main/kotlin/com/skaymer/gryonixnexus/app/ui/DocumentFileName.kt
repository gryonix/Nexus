package com.skaymer.gryonixnexus.app.ui

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns

object DocumentFileName {
    fun of(context: Context, uri: Uri): String {
        var provided: String? = null
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (column >= 0 && cursor.moveToFirst()) provided = cursor.getString(column)
            }
        return choose(provided, uri.lastPathSegment)
    }

    fun choose(providerName: String?, lastPathSegment: String?): String {
        providerName?.takeIf { it.isNotBlank() }?.let { return it }
        return lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
            ?: "backup.tar.gz"
    }
}
