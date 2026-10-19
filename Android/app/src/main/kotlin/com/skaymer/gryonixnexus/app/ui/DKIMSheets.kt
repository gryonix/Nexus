package com.skaymer.gryonixnexus.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.app.dns.DKIMViewModel
import com.skaymer.gryonixnexus.app.dns.DKIMZones
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.configurator.DNSProviderKind
import com.skaymer.gryonixnexus.app.configurator.DNSProviderPublishModel
import com.skaymer.gryonixnexus.app.secrets.DNSCredentialTokenStore
import com.skaymer.gryonixnexus.servercontrol.DKIMRecord
import androidx.compose.runtime.key
import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.servercontrol.DKIMExport
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun DKIMCard(onOpen: () -> Unit, showDivider: Boolean = true) {
    ValueRow(
        title = stringResource(R.string.dkim_title),
        value = null,
        onClick = onOpen,
        showDivider = showDivider,
    )
}

@Composable
fun DKIMDialog(
    deployment: Deployment,
    dkim: DKIMViewModel,
    onClose: () -> Unit,
) {
    val state by dkim.state.collectAsState()
    val clipboard = LocalClipboardManager.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val bundle = DKIMExport.bundle(
        records = state.records,
        zoneSummary = stringResource(R.string.dkim_zone_summary),
        csvSummary = stringResource(R.string.dkim_csv_summary),
    )
    var saving by remember(deployment.id) { mutableStateOf<Artifact?>(null) }
    var exportError by remember(deployment.id) { mutableStateOf<String?>(null) }

    val saveTo = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("*/*"),
    ) { uri ->
        val artifact = saving
        saving = null
        if (uri == null || artifact == null) return@rememberLauncherForActivityResult
        scope.launch {
            val wrote = withContext(Dispatchers.IO) {
                runCatching {
                    context.contentResolver.openOutputStream(uri)
                        ?.use { it.write(artifact.contents.toByteArray()) }
                }.isSuccess
            }
            exportError = if (wrote) null else context.getString(R.string.dkim_export_failed)
        }
    }

    LaunchedEffect(deployment.id) { dkim.load(deployment) }
    DisposableEffect(deployment.id) { onDispose { dkim.reset() } }

    IOSSheet(
        title = stringResource(R.string.dkim_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_done),
        action = SheetAction(
            title = stringResource(R.string.service_logs_copy),
            enabled = state.records.isNotEmpty(),
            onSelect = { clipboard.setText(AnnotatedString(state.copyText())) },
        ),
    ) {
        Text(
            stringResource(R.string.dkim_why),
            style = MaterialTheme.typography.bodyMedium,
            color = Gryonix.colors.secondaryLabel,
            modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
        )
        when {
            state.isLoading && state.records.isEmpty() -> Row(
                Modifier.padding(horizontal = Metrics.listInset + 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CircularProgressIndicator(
                    Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = Gryonix.colors.tertiaryLabel,
                )
                Text(
                    stringResource(R.string.mailboxes_loading),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
            state.errorMessage != null -> Text(
                state.errorMessage!!,
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.danger,
                modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
            )
            state.saysTheKeyIsNotReady -> Text(
                stringResource(R.string.dkim_not_ready),
                style = MaterialTheme.typography.bodyMedium,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
            )
            else -> SelectionContainer {
                Column(verticalArrangement = Arrangement.spacedBy(Metrics.sectionGap)) {
                    state.records.forEach { record ->
                        GroupedSection(header = record.name, footer = record.type) {
                            GroupedRow(showDivider = false) {
                                Text(
                                    record.value,
                                    style = MaterialTheme.typography.bodySmall,
                                    fontFamily = FontFamily.Monospace,
                                    color = Gryonix.colors.label,
                                )
                            }
                        }
                    }
                }
            }
        }
        if (state.records.isNotEmpty()) DKIMPublishCard(state.records)
        if (bundle != null) {
            GroupedSection(
                footer = exportError ?: stringResource(R.string.dkim_export_hint),
            ) {
                ActionRow(
                    text = stringResource(R.string.dkim_export_zone),
                    onClick = {
                        saving = bundle.zoneFile
                        saveTo.launch(bundle.zoneFile.fileName)
                    },
                )
                ActionRow(
                    text = stringResource(R.string.dkim_export_csv),
                    onClick = {
                        saving = bundle.csvFile
                        saveTo.launch(bundle.csvFile.fileName)
                    },
                    showDivider = false,
                )
            }
        }
    }
}

/** Sends every domain's DKIM record to the saved DNS provider */
@Composable
private fun DKIMPublishCard(records: List<DKIMRecord>) {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val zones = remember(records) { DKIMZones.zones(records) }
    val model = remember {
        DNSProviderPublishModel(
            app.dnsCredentials,
            DNSCredentialTokenStore(app.secrets),
            initialProviderKind = app.dnsCredentials.selected?.kind ?: DNSProviderKind.CLOUDFLARE,
        )
    }
    key(zones) { DNSProviderPublishCard(zones, model, onPublishSucceeded = {}) }
}
