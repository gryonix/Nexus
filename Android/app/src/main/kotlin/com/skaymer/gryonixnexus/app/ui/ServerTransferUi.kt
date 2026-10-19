package com.skaymer.gryonixnexus.app.ui

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.DeploymentTransfer
import com.skaymer.gryonixnexus.app.servers.DeploymentTransferService
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.AlertFields
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.TransferSeal
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What waits on a passphrase */
sealed class TransferPrompt {
    class Export(val deployments: List<Deployment>, val many: Boolean) : TransferPrompt()

    class Unlock(val data: ByteArray) : TransferPrompt()
}

/** Sealed export, passphrase import and the replace question */
class ServerTransferUi(
    private val transfer: DeploymentTransferService,
    private val known: () -> List<Deployment>,
    private val onImported: () -> Unit,
    private val scope: CoroutineScope,
    private val context: Context,
) {
    var prompt by mutableStateOf<TransferPrompt?>(null)
    var promptError by mutableStateOf<String?>(null)
    var replacing by mutableStateOf<DeploymentTransfer?>(null)
    var failure by mutableStateOf<String?>(null)
    internal var pending: List<Deployment> = emptyList()
    internal var passphrase = ""
    internal lateinit var launchOne: (String) -> Unit
    internal lateinit var launchMany: () -> Unit
    internal lateinit var launchRead: () -> Unit

    fun exportOne(deployment: Deployment) = ask(TransferPrompt.Export(listOf(deployment), many = false))

    fun exportMany(deployments: List<Deployment>) = ask(TransferPrompt.Export(deployments, many = true))

    fun import() = launchRead()

    private fun ask(next: TransferPrompt) {
        promptError = null
        prompt = next
    }

    fun submit(current: TransferPrompt, typed: String) {
        when (current) {
            is TransferPrompt.Export -> {
                prompt = null
                passphrase = typed
                pending = current.deployments
                if (current.many) launchMany() else launchOne(DeploymentTransferService.fileName(pending.first()))
            }
            is TransferPrompt.Unlock -> scope.launch(Dispatchers.IO) { unlock(current.data, typed) }
        }
    }

    private suspend fun unlock(data: ByteArray, typed: String) {
        val opened = runCatching { TransferSeal.open(data, typed) }
        withContext(Dispatchers.Main) {
            opened.onSuccess { prompt = null }
            val error = opened.exceptionOrNull()
            if (error is TransferSeal.WrongPassphrase) {
                promptError = context.getString(R.string.transfer_wrong_passphrase)
            } else if (error != null) {
                prompt = null
                failure = error.message
            }
        }
        opened.getOrNull()?.let { offer(it) }
    }

    /** A picked file, sealed or from an older app */
    fun received(data: ByteArray) {
        if (TransferSeal.isSealed(data)) {
            scope.launch(Dispatchers.Main) { ask(TransferPrompt.Unlock(data)) }
        } else {
            scope.launch(Dispatchers.IO) { offer(data) }
        }
    }

    private suspend fun offer(plain: ByteArray) {
        val decoded = runCatching { transfer.decode(plain.decodeToString()) }
        withContext(Dispatchers.Main) {
            val incoming = decoded.getOrElse { failure = it.message; return@withContext }
            if (known().any { it.id == incoming.deployment.id }) replacing = incoming else apply(incoming)
        }
    }

    fun confirmReplace() {
        val incoming = replacing ?: return
        replacing = null
        apply(incoming)
    }

    private fun apply(incoming: DeploymentTransfer) {
        scope.launch(Dispatchers.IO) {
            val outcome = runCatching { transfer.apply(incoming) }
            withContext(Dispatchers.Main) {
                failure = outcome.exceptionOrNull()?.message
                if (outcome.isSuccess) onImported()
            }
        }
    }

    /** One sealed file per server */
    internal suspend fun sealed(deployment: Deployment): ByteArray =
        TransferSeal.seal(transfer.encode(transfer.exportFor(deployment)).toByteArray(), passphrase)

    internal fun write(block: suspend () -> Unit) {
        scope.launch(Dispatchers.IO) {
            val error = runCatching { block() }.exceptionOrNull()
            passphrase = ""
            withContext(Dispatchers.Main) { failure = error?.message }
        }
    }
}

@Composable
fun rememberServerTransfer(
    transfer: DeploymentTransferService,
    known: () -> List<Deployment>,
    onImported: () -> Unit,
): ServerTransferUi {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val ui = remember(transfer) { ServerTransferUi(transfer, known, onImported, scope, context) }
    val writeOne = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        val deployment = ui.pending.firstOrNull()
        if (uri != null && deployment != null) ui.write { writeFile(context, uri, ui.sealed(deployment)) }
    }
    val writeMany = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { tree ->
        val chosen = ui.pending
        if (tree != null && chosen.isNotEmpty()) ui.write { writeFolder(context, tree, chosen, ui) }
    }
    val read = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val bytes = runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }
        bytes.getOrNull()?.let(ui::received) ?: run { ui.failure = bytes.exceptionOrNull()?.message }
    }
    ui.launchOne = { writeOne.launch(it) }
    ui.launchMany = { writeMany.launch(null) }
    ui.launchRead = { read.launch(arrayOf("*/*")) }
    return ui
}

private fun writeFile(context: Context, uri: Uri, bytes: ByteArray) {
    context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) } ?: error("the file could not be written")
}

private suspend fun writeFolder(context: Context, tree: Uri, chosen: List<Deployment>, ui: ServerTransferUi) {
    val folder = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
    for (deployment in chosen) {
        val name = DeploymentTransferService.fileName(deployment)
        val file = DocumentsContract.createDocument(context.contentResolver, folder, "application/json", name)
            ?: error("could not write \"$name\"")
        writeFile(context, file, ui.sealed(deployment))
    }
}

/** The passphrase dialog, the replace question and failures */
@Composable
fun ServerTransferDialogs(ui: ServerTransferUi) {
    ui.prompt?.let { prompt -> TransferPassphraseDialog(ui, prompt) }
    ui.replacing?.let { incoming ->
        ConfirmAlert(
            title = stringResource(R.string.transfer_replace_title),
            message = stringResource(R.string.transfer_replace_message, incoming.deployment.name),
            confirm = stringResource(R.string.transfer_replace_confirm),
            cancel = stringResource(R.string.group_cancel),
            destructive = true,
            onConfirm = { ui.confirmReplace() },
            onCancel = { ui.replacing = null },
        )
    }
    ui.failure?.let { message ->
        IOSAlert(
            title = stringResource(R.string.transfer_failed),
            message = message,
            onDismiss = { ui.failure = null },
            actions = listOf(AlertAction(stringResource(R.string.group_done), preferred = true) { ui.failure = null }),
        )
    }
}

@Composable
private fun TransferPassphraseDialog(ui: ServerTransferUi, prompt: TransferPrompt) {
    val exporting = prompt is TransferPrompt.Export
    var typed by remember(prompt) { mutableStateOf("") }
    var repeated by remember(prompt) { mutableStateOf("") }
    val ready = if (exporting) typed.length >= MINIMUM_PASSPHRASE && typed == repeated else typed.isNotEmpty()
    IOSAlert(
        title = stringResource(if (exporting) R.string.transfer_protect_title else R.string.transfer_open_title),
        message = listOfNotNull(
            stringResource(if (exporting) R.string.transfer_protect_message else R.string.transfer_open_message),
            ui.promptError,
        ).joinToString("\n\n"),
        onDismiss = { ui.prompt = null },
        actions = listOf(
            AlertAction(stringResource(R.string.group_cancel)) { ui.prompt = null },
            AlertAction(
                stringResource(if (exporting) R.string.export_server_confirm else R.string.transfer_open_confirm),
                preferred = true,
                enabled = ready,
            ) { ui.submit(prompt, typed) },
        ),
    ) {
        AlertFields {
            PassphraseField(R.string.transfer_passphrase, typed, showDivider = exporting) { typed = it }
            if (exporting) {
                PassphraseField(R.string.transfer_passphrase_repeat, repeated, showDivider = false) { repeated = it }
            }
        }
    }
}

@Composable
private fun PassphraseField(label: Int, value: String, showDivider: Boolean, onChange: (String) -> Unit) {
    FieldRow(
        label = stringResource(label),
        value = value,
        onValueChange = onChange,
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        showDivider = showDivider,
    )
}

private const val MINIMUM_PASSPHRASE = 8
