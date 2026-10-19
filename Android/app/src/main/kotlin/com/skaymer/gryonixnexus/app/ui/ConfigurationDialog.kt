package com.skaymer.gryonixnexus.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.configurator.ConfigurationExport
import com.skaymer.gryonixnexus.app.configurator.DNSProviderKind
import com.skaymer.gryonixnexus.app.configurator.DNSProviderPublishModel
import com.skaymer.gryonixnexus.app.secrets.DNSCredentialTokenStore
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.core.DNSRecord
import com.skaymer.gryonixnexus.recipe.ConfigurationExportFormat
import com.skaymer.gryonixnexus.recipe.sortedByPort
import com.skaymer.gryonixnexus.recipe.sortedByProtocol
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun ConfigurationDialog(
    deployment: Deployment,
    recorded: com.skaymer.gryonixnexus.app.configurator.ConfiguratorForm?,
    onClose: () -> Unit,
) {
    val clipboard = LocalClipboardManager.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val portsTxtSummary = context.getString(R.string.configuration_ports_txt_summary)
    val portsCsvSummary = context.getString(R.string.configuration_ports_csv_summary)
    val bundle = remember(deployment.id, recorded) {
        ConfigurationExport.build(
            deployment = deployment,
            recorded = recorded,
            portsTxtSummary = portsTxtSummary,
            portsCsvSummary = portsCsvSummary,
        )
    }
    var saving by remember(deployment.id) { mutableStateOf<Artifact?>(null) }
    var exportError by remember(deployment.id) { mutableStateOf<String?>(null) }
    var sortPortsByProtocol by remember(deployment.id) { mutableStateOf(false) }

    val sortedPorts = remember(bundle.ports, sortPortsByProtocol) {
        bundle.ports?.let { ports ->
            val requirements = if (sortPortsByProtocol) {
                ports.requirements.sortedByProtocol()
            } else {
                ports.requirements.sortedByPort()
            }
            ports.copy(
                requirements = requirements,
                copyText = ConfigurationExportFormat.portsText(requirements),
                txtFile = ConfigurationExportFormat.portsTextArtifact(requirements, portsTxtSummary),
                csvFile = ConfigurationExportFormat.portsCSVArtifact(requirements, portsCsvSummary),
            )
        }
    }

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

    fun save(artifact: Artifact) {
        saving = artifact
        saveTo.launch(artifact.fileName)
    }

    IOSSheet(
        title = stringResource(R.string.configuration_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_done),
    ) {
        if (bundle.dns.isEmpty() && bundle.ports == null) {
            Text(
                stringResource(R.string.configuration_nothing),
                style = MaterialTheme.typography.bodyMedium,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
            )
        }

        bundle.dns.forEach { zone ->
            GroupedSection(header = zone.domain) {
                GroupedRow {
                    SelectionContainer {
                        Text(
                            zone.copyText,
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace,
                            color = Gryonix.colors.label,
                        )
                    }
                }
                ActionRow(
                    text = stringResource(R.string.service_logs_copy),
                    onClick = { clipboard.setText(AnnotatedString(zone.copyText)) },
                    showDivider = zone.zoneFile != null || zone.csvFile != null,
                )
                zone.zoneFile?.let { file ->
                    ActionRow(
                        text = stringResource(R.string.dkim_export_zone),
                        onClick = { save(file) },
                        showDivider = zone.csvFile != null,
                    )
                }
                zone.csvFile?.let { file ->
                    ActionRow(
                        text = stringResource(R.string.dkim_export_csv),
                        onClick = { save(file) },
                        showDivider = false,
                    )
                }
            }
        }

        ConfigurationPublishCard(deployment, bundle.dns)

        sortedPorts?.let { ports ->
            GroupedSection(
                header = stringResource(R.string.configuration_ports),
                note = stringResource(R.string.configuration_ports_hint),
                footer = exportError,
            ) {
                GroupedRow {
                    IOSSegmentedControl(
                        segments = listOf(false, true),
                        selected = sortPortsByProtocol,
                        label = {
                            stringResource(
                                if (it) R.string.configuration_ports_sort_protocol
                                else R.string.configuration_ports_sort_port
                            )
                        },
                        onSelect = { sortPortsByProtocol = it },
                    )
                }
                GroupedRow {
                    SelectionContainer {
                        Text(
                            ports.copyText,
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace,
                            color = Gryonix.colors.label,
                        )
                    }
                }
                ActionRow(
                    text = stringResource(R.string.service_logs_copy),
                    onClick = { clipboard.setText(AnnotatedString(ports.copyText)) },
                )
                ActionRow(
                    text = stringResource(R.string.configuration_save_txt),
                    onClick = { save(ports.txtFile) },
                )
                ActionRow(
                    text = stringResource(R.string.dkim_export_csv),
                    onClick = { save(ports.csvFile) },
                    showDivider = false,
                )
            }
        }
    }
}

/** Publishes every record above through the saved DNS token */
@Composable
private fun ConfigurationPublishCard(deployment: Deployment, zones: List<ConfigurationExport.DNSZone>) {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val publishable = remember(deployment.id, zones) { publishableZones(deployment, zones) }
    if (publishable.isEmpty()) return
    val model = remember {
        DNSProviderPublishModel(
            app.dnsCredentials,
            DNSCredentialTokenStore(app.secrets),
            initialProviderKind = app.dnsCredentials.selected?.kind ?: DNSProviderKind.CLOUDFLARE,
        )
    }
    key(publishable) { DNSProviderPublishCard(publishable, model, onPublishSucceeded = {}) }
}

/** Drops address records behind a tunnel or offline */
internal fun publishableZones(
    deployment: Deployment,
    zones: List<ConfigurationExport.DNSZone>,
): List<ConfigurationExport.DNSZone> {
    val addressesAllowed = deployment.scope.publishesAddressRecords &&
        ServiceID.CLOUDFLARED !in deployment.services
    return zones.mapNotNull { zone ->
        val withEntry = zone.records + listOfNotNull(entryRecord(deployment.entry.host, zone.domain, zone.records))
        val records = withEntry.filter { addressesAllowed || !it.isAddress() }
        if (records.isEmpty()) null else zone.copy(records = records)
    }
}

/** The name the app connects by, pointed at the server */
internal fun entryRecord(rawHost: String, zone: String, records: List<DNSRecord>): DNSRecord? {
    val host = rawHost.trim().lowercase()
    val domain = zone.lowercase()
    if (host != domain && !host.endsWith(".$domain")) return null
    if (records.any { it.name.lowercase() == host && it.isAddress() }) return null
    val address = records.firstOrNull { it.isAddress() } ?: return null
    return DNSRecord(host, address.type, address.value)
}

private fun DNSRecord.isAddress() =
    type == DNSRecord.RecordType.A || type == DNSRecord.RecordType.AAAA
