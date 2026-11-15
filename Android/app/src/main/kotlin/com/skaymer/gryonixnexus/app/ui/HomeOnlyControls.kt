package com.skaymer.gryonixnexus.app.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.CertificateDownloads
import com.skaymer.gryonixnexus.app.servers.HomeOnlyController
import com.skaymer.gryonixnexus.app.servers.HomeOnlyDNS
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.ApplyPendingBar
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.InternalCertificate
import com.skaymer.gryonixnexus.servercontrol.PublicPortProbe
import kotlinx.coroutines.launch

@Composable
fun HomeOnlyRow(service: ManagedService, deployment: Deployment, controller: HomeOnlyController?) {
    if (controller == null || !HomeOnlyController.offers(deployment, service)) return
    val homeOnly = HomeOnlyController.isHomeOnly(deployment, service.id)
    val hasSite = service.webIngress(deployment.serviceContext) != null
    val applying by controller.applying.collectAsState()
    val noVPN = service.id in deployment.homeOnlyNoVPN
    var homeDraft by remember(deployment.id, service.id, homeOnly) { mutableStateOf<Boolean?>(null) }
    var noVPNDraft by remember(deployment.id, service.id, noVPN) { mutableStateOf<Boolean?>(null) }
    ToggleRow(
        title = stringResource(R.string.home_only_title),
        subtitle = stringResource(R.string.home_only_note),
        checked = homeDraft ?: homeOnly,
        enabled = service.id !in applying,
        onCheckedChange = { homeDraft = it },
        showDivider = false,
    )
    HomeOnlyFailureLine(service, deployment, controller, busy = service.id in applying)
    if (homeOnly && hasSite) {
        ToggleRow(
            title = stringResource(R.string.home_only_also_vpn),
            subtitle = stringResource(R.string.home_only_also_vpn_note),
            checked = !(noVPNDraft ?: noVPN),
            onCheckedChange = { noVPNDraft = !it },
            showDivider = false,
        )
    }
    val homeWaits = homeDraft != null && homeDraft != homeOnly
    val vpnWaits = noVPNDraft != null && noVPNDraft != noVPN
    ApplyPendingBar(
        visible = homeWaits || vpnWaits,
        apply = stringResource(R.string.airplay_apply),
        cancel = stringResource(R.string.pending_changes_cancel),
        onApply = {
            if (homeWaits) controller.set(deployment, service, homeDraft == true)
            else if (vpnWaits) controller.setNoVPN(deployment, service, noVPNDraft == true)
        },
        onRevert = { homeDraft = null; noVPNDraft = null },
    )
    if (homeOnly) service.webIngress(deployment.serviceContext)?.let {
        HomeLocalNameRow(deployment, it.hostname, controller)
        HomeOnlyReachLine(it.hostname)
    }
    if (homeOnly) PublicPortsStatus(service, deployment, controller)
}

/** Why the switch did not apply, with a retry */
@Composable
private fun HomeOnlyFailureLine(service: ManagedService, deployment: Deployment, controller: HomeOnlyController, busy: Boolean) {
    val failures by controller.failures.collectAsState()
    val failure = failures[service.id] ?: return
    if (busy) return
    val line = when (failure) {
        is HomeOnlyController.Failure.AgentTooOld -> stringResource(R.string.system_update_agent_too_old)
        is HomeOnlyController.Failure.Told -> failure.message
    }
    Column {
        Text(
            line,
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.warning,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )
        ActionRow(
            stringResource(R.string.config_try_again),
            onClick = { controller.set(deployment, service, HomeOnlyController.isHomeOnly(deployment, service.id)) },
            showDivider = false,
        )
    }
}

@Composable
private fun PublicPortsStatus(service: ManagedService, deployment: Deployment, controller: HomeOnlyController) {
    val verdicts by controller.verdicts.collectAsState()
    val verdict = verdicts[service.id] ?: return
    val scope = rememberCoroutineScope()
    val line = when (verdict) {
        is PublicPortProbe.Verdict.Closed -> stringResource(R.string.home_only_probe_closed)
        is PublicPortProbe.Verdict.Open ->
            stringResource(R.string.home_only_probe_open, verdict.ports.joinToString(", "))
    }
    Column {
        Text(
            line,
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.secondaryLabel,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )
        ActionRow(
            stringResource(R.string.home_only_probe_recheck),
            onClick = { scope.launch { controller.check(deployment, service) } },
            showDivider = false,
        )
    }
}

/** Publishes or removes the service's address record */
@Composable
internal fun SiteDNSControls(service: ManagedService, deployment: Deployment, controller: HomeOnlyController) {
    val dns = controller.dns ?: return
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var report by remember { mutableStateOf<List<String>>(emptyList()) }
    var manual by remember { mutableStateOf<HomeOnlyDNS.Manual?>(null) }
    val removed = service.id in deployment.homeOnlyDNSRemoved
    val action = if (removed) HomeOnlyDNS.Action.RESTORE else HomeOnlyDNS.Action.REMOVE
    ActionRow(
        stringResource(if (removed) R.string.home_only_dns_restore else R.string.home_only_dns_remove),
        enabled = !busy,
        showDivider = false,
        onClick = {
            busy = true
            scope.launch {
                when (val outcome = dns.change(action, service, deployment)) {
                    is HomeOnlyDNS.Outcome.Done -> {
                        report = outcome.lines
                        controller.markDNSRemoved(deployment, service, !removed)
                    }
                    is HomeOnlyDNS.Outcome.Failed -> report = outcome.lines
                    is HomeOnlyDNS.Outcome.ByHand -> manual = outcome.manual
                }
                busy = false
            }
        },
    )
    Text(
        stringResource(
            if (HomeOnlyController.isHomeOnly(deployment, service.id)) R.string.home_only_dns_warning
            else R.string.site_dns_note,
        ),
        style = MaterialTheme.typography.bodySmall,
        color = Gryonix.colors.secondaryLabel,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
    )
    report.forEach {
        Text(it, style = MaterialTheme.typography.bodySmall, color = Gryonix.colors.secondaryLabel, modifier = Modifier.padding(horizontal = 16.dp))
    }
    manual?.let { pending ->
        DNSByHandSheet(
            pending,
            onDismiss = { manual = null },
            onDone = {
                controller.markDNSRemoved(deployment, service, pending.action == HomeOnlyDNS.Action.REMOVE)
                manual = null
            },
        )
    }
}

@Composable
private fun DNSByHandSheet(manual: HomeOnlyDNS.Manual, onDismiss: () -> Unit, onDone: () -> Unit) {
    IOSSheet(
        title = stringResource(R.string.home_only_dns_manual_title),
        onClose = onDismiss,
        closeLabel = stringResource(R.string.actions_done),
        action = SheetAction(stringResource(R.string.actions_done), onSelect = onDone),
    ) {
        Text(
            stringResource(
                if (manual.action == HomeOnlyDNS.Action.REMOVE) R.string.home_only_dns_manual_remove
                else R.string.home_only_dns_manual_add,
            ),
            modifier = Modifier.padding(16.dp),
        )
        manual.lines.forEach { Text(it, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) }
    }
}

/** Offers the server's own root certificate to this device */
@Composable
fun InternalCertificateRow(service: ManagedService, deployment: Deployment, controller: HomeOnlyController?) {
    if (controller == null || !deployment.scope.usesInternalTLS || service.webIngress(deployment.serviceContext) == null) return
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var note by remember { mutableStateOf<String?>(null) }
    val noCert = stringResource(R.string.home_only_no_cert)
    val installNote = stringResource(R.string.home_only_trust_cert_android)
    ActionRow(
        stringResource(R.string.home_only_trust_cert),
        showDivider = false,
        onClick = {
            scope.launch {
                val pem = runCatching { controller.rootCA(deployment) }.getOrDefault("")
                note = if (!InternalCertificate.isPem(pem)) {
                    noCert
                } else if (CertificateDownloads.save(context, InternalCertificate.fileName(deployment.name), pem)) {
                    CertificateDownloads.openInstallSettings(context)
                    installNote
                } else {
                    Toast.makeText(context, noCert, Toast.LENGTH_LONG).show()
                    noCert
                }
            }
        },
    )
    note?.let {
        Text(it, style = MaterialTheme.typography.bodySmall, color = Gryonix.colors.secondaryLabel, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
    }
}

/** The site's second name, answered on the home network */
@Composable
private fun HomeLocalNameRow(deployment: Deployment, host: String, controller: HomeOnlyController) {
    var alias by remember(host) { mutableStateOf<String?>(null) }
    var loaded by remember(host) { mutableStateOf(false) }
    var error by remember(host) { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    androidx.compose.runtime.LaunchedEffect(deployment.id, host) {
        alias = runCatching { controller.localAliases(deployment, null, false)[host] }.getOrNull()
        loaded = true
    }
    val proposed = host.substringBefore('.') + ".local"
    var draft by remember(host, alias) { mutableStateOf<Boolean?>(null) }
    ToggleRow(
        title = stringResource(R.string.home_only_local_name, proposed),
        subtitle = error ?: stringResource(R.string.home_only_local_name_note),
        checked = draft ?: (alias != null),
        enabled = loaded,
        onCheckedChange = { draft = it },
        showDivider = false,
    )
    ApplyPendingBar(
        visible = draft != null && draft != (alias != null),
        apply = stringResource(R.string.airplay_apply),
        cancel = stringResource(R.string.pending_changes_cancel),
        onApply = {
            val on = draft == true
            loaded = false
            scope.launch {
                runCatching { controller.localAliases(deployment, host, on)[host] }
                    .onSuccess { alias = it; error = null }
                    .onFailure { error = it.message ?: it.toString() }
                draft = null
                loaded = true
            }
        },
        onRevert = { draft = null },
    )
}

/** One line saying whether the site opens from here */
@Composable
private fun HomeOnlyReachLine(host: String) {
    var reach by remember(host) { mutableStateOf(com.skaymer.gryonixnexus.app.servers.HomeOnlyReach.CHECKING) }
    androidx.compose.runtime.LaunchedEffect(host) { reach = com.skaymer.gryonixnexus.app.servers.HomeOnlyReach.check(host) }
    val (text, color) = when (reach) {
        com.skaymer.gryonixnexus.app.servers.HomeOnlyReach.CHECKING ->
            stringResource(R.string.home_only_reach_checking) to Gryonix.colors.secondaryLabel
        com.skaymer.gryonixnexus.app.servers.HomeOnlyReach.OPENS ->
            stringResource(R.string.home_only_reach_opens) to Gryonix.colors.success
        com.skaymer.gryonixnexus.app.servers.HomeOnlyReach.CLOSED_HERE ->
            stringResource(R.string.home_only_reach_closed) to Gryonix.colors.warning
    }
    Text(text, style = MaterialTheme.typography.bodySmall, color = color,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
}
