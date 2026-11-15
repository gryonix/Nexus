package com.skaymer.gryonixnexus.app.ui

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import com.skaymer.gryonixnexus.app.ui.design.Separator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.profile.advanced.SubscriptionImport
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.vpn.ForeignTunnelConfig
import com.skaymer.gryonixnexus.catalog.ServiceRegistry

/** Adds a tunnel from a configuration of another server */
@Composable
fun ImportTunnelSheet(onAdd: (ForeignTunnelConfig.Detected, String) -> Unit, onClose: () -> Unit) {
    val context = LocalContext.current
    var text by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var nameTyped by remember { mutableStateOf(false) }
    var scanning by remember { mutableStateOf(false) }
    val detection = remember(text) { runCatching { ForeignTunnelConfig.detect(text) } }
    val detected = detection.getOrNull()
    val advancedCount = remember(text, detected) { if (detected == null) advancedServers(text) else null }
    LaunchedEffect(detected?.suggestedName) { if (!nameTyped) detected?.let { name = it.suggestedName } }
    val pickFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { readText(context, it) }?.let { text = it }
    }
    IOSSheet(
        title = stringResource(R.string.vpn_config),
        onClose = onClose,
        closeLabel = stringResource(R.string.close),
        action = SheetAction(stringResource(R.string.vpn_on_demand_add), enabled = detected != null || advancedCount != null) {
            if (advancedCount != null) {
                (context.applicationContext as GryonixApplication).advancedVpn.importText(text)
                onClose()
            }
            detected?.let { onAdd(it, name); onClose() }
        },
    ) {
        GroupedSection(header = stringResource(R.string.vpn_import_title), note = stringResource(R.string.vpn_import_footer)) {
            ConfigurationTextArea(text) { text = it }
            ActionRow(stringResource(R.string.vpn_import_paste), onClick = { clipboardText(context)?.let { text = it } })
            ActionRow(stringResource(R.string.vpn_import_file), onClick = { pickFile.launch(arrayOf("*/*")) })
            ActionRow(stringResource(R.string.vpn_import_scan), onClick = { scanning = !scanning }, showDivider = false)
        }
        if (advancedCount != null) AdvancedVerdict(advancedCount) else if (text.isNotBlank()) ImportVerdict(detection)
        if (scanning) {
            Column(Modifier.fillMaxWidth().padding(16.dp)) {
                QuickTransferScanner(R.string.vpn_import_scan_bad_image) { code ->
                    val readable = runCatching { ForeignTunnelConfig.detect(code) }.isSuccess || advancedServers(code) != null
                    if (readable) { text = code; scanning = false }
                    readable
                }
            }
        }
        GroupedSection {
            FieldRow(label = stringResource(R.string.name_label), value = name, placeholder = detected?.suggestedName ?: "",
                onValueChange = { name = it; nameTyped = true }, showDivider = false)
        }
    }
}

/** The pasted configuration, monospaced and left to right */
@Composable
private fun ConfigurationTextArea(text: String, onChange: (String) -> Unit) {
    val colors = Gryonix.colors
    val style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace, color = colors.label)
    Column {
        BasicTextField(
            value = text,
            onValueChange = onChange,
            textStyle = style,
            cursorBrush = SolidColor(colors.accent),
            keyboardOptions = KeyboardOptions(autoCorrectEnabled = false, capitalization = KeyboardCapitalization.None),
            modifier = Modifier.fillMaxWidth().heightIn(min = 140.dp, max = 260.dp).padding(16.dp),
            decorationBox = { field ->
                if (text.isEmpty()) Text("[Interface] · vpn:// · ss:// · vless://", style = style.copy(color = colors.tertiaryLabel))
                field()
            },
        )
        Separator(startInset = 16.dp)
    }
}

/** Servers a list, a link or a Clash profile holds */
private fun advancedServers(text: String): Int? =
    if (text.isBlank()) null else SubscriptionImport.parse(text).servers.size.takeIf { it > 0 }

@Composable
private fun AdvancedVerdict(count: Int) {
    Column(Modifier.padding(horizontal = 20.dp)) {
        Text(
            stringResource(R.string.vpn_import_advanced_count, count),
            style = MaterialTheme.typography.bodyMedium,
            color = Gryonix.colors.success,
        )
        Text(
            stringResource(R.string.vpn_import_advanced_note),
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.secondaryLabel,
        )
    }
}

@Composable
private fun ImportVerdict(detection: Result<ForeignTunnelConfig.Detected>) {
    val found = detection.getOrNull()
    val line = found?.let { ServiceRegistry.service(it.protocol)?.displayName ?: it.protocol.rawValue }
        ?: failureText(detection.exceptionOrNull())
    Text(
        line,
        style = MaterialTheme.typography.bodyMedium,
        color = if (found != null) Gryonix.colors.success else Gryonix.colors.warning,
        modifier = Modifier.padding(horizontal = 20.dp),
    )
}

@Composable
private fun failureText(error: Throwable?): String = when (error) {
    is ForeignTunnelConfig.Failure.NotCarried -> stringResource(
        R.string.vpn_import_not_carried, ServiceRegistry.service(error.protocol)?.displayName ?: error.protocol.rawValue,
    )
    ForeignTunnelConfig.Failure.Unreadable -> stringResource(R.string.vpn_import_unreadable)
    ForeignTunnelConfig.Failure.Empty -> stringResource(R.string.vpn_import_empty)
    else -> stringResource(R.string.vpn_import_unknown)
}

private fun clipboardText(context: Context): String? =
    context.getSystemService(ClipboardManager::class.java)?.primaryClip?.takeIf { it.itemCount > 0 }
        ?.getItemAt(0)?.coerceToText(context)?.toString()

private const val MAX_FILE_BYTES = 1_000_000

private fun readText(context: Context, uri: Uri): String? = runCatching {
    context.contentResolver.openInputStream(uri)?.use { stream ->
        val bytes = stream.buffered().readBytesUpTo(MAX_FILE_BYTES + 1)
        if (bytes.size > MAX_FILE_BYTES) null else bytes.decodeToString()
    }
}.getOrNull()

private fun java.io.InputStream.readBytesUpTo(limit: Int): ByteArray {
    val out = java.io.ByteArrayOutputStream()
    val buffer = ByteArray(8_192)
    while (out.size() < limit) {
        val read = read(buffer, 0, minOf(buffer.size, limit - out.size()))
        if (read < 0) break
        out.write(buffer, 0, read)
    }
    return out.toByteArray()
}
