package com.skaymer.gryonixnexus.app.ui

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.BackupsViewModel
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.FleetBackup
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Saves backups from the server to this device */
internal class BackupSaver(
    val saveOne: (FleetBackup) -> Unit,
    val saveMany: (List<FleetBackup>) -> Unit,
)

@Composable
internal fun rememberBackupSaver(deployment: Deployment, backups: BackupsViewModel): BackupSaver {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pending = remember { Pending() }

    fun save(row: FleetBackup, write: suspend (ByteArray) -> Boolean) {
        backups.download(deployment, ServiceID(row.serviceId), row.entry) { bytes, _ ->
            scope.launch(Dispatchers.IO) {
                if (!write(bytes)) {
                    withContext(Dispatchers.Main) {
                        Toast.makeText(context, R.string.dkim_export_failed, Toast.LENGTH_LONG).show()
                    }
                }
            }
        }
    }

    val oneFile = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/gzip"),
    ) { uri ->
        val row = pending.row
        pending.row = null
        if (uri != null && row != null) save(row) { writeTo(context, uri, it) }
    }
    val folder = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { tree ->
        val rows = pending.rows
        pending.rows = emptyList()
        if (tree != null) rows.forEach { row -> save(row) { writeInto(context, tree, row.entry.displayName, it) } }
    }
    return remember {
        BackupSaver(
            saveOne = { row ->
                pending.row = row
                oneFile.launch(row.entry.displayName)
            },
            saveMany = { rows ->
                pending.rows = rows
                if (rows.isNotEmpty()) folder.launch(null)
            },
        )
    }
}

private class Pending {
    var row: FleetBackup? = null
    var rows: List<FleetBackup> = emptyList()
}

private fun writeTo(context: Context, uri: Uri, bytes: ByteArray): Boolean = runCatching {
    context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) } != null
}.getOrDefault(false)

private fun writeInto(context: Context, tree: Uri, name: String, bytes: ByteArray): Boolean = runCatching {
    val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
    val file = DocumentsContract.createDocument(context.contentResolver, parent, "application/gzip", name)
        ?: return@runCatching false
    writeTo(context, file, bytes)
}.getOrDefault(false)
