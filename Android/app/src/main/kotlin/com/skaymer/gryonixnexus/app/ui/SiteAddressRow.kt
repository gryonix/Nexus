package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.HomeOnlyDNS
import com.skaymer.gryonixnexus.app.ui.design.ApplyPendingBar
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceHostnames
import com.skaymer.gryonixnexus.catalog.SiteAddress
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.launch

/** The service's web address, changeable, with its DNS record */
@Composable
internal fun SiteAddressRow(service: ManagedService, deployment: Deployment, tools: ServiceTools?) {
    val reapply = tools?.reapply ?: return
    val slot = ServiceHostnames.settings[service.id] ?: return
    val ingress = service.webIngress(deployment.serviceContext) ?: return
    val scope = rememberCoroutineScope()
    var typed by remember(deployment.id, service.id) { mutableStateOf("") }
    val asked = SiteAddress.normalized(typed)
    OwnAddressRow(stringResource(R.string.site_address), typed, { typed = it }, placeholder = ingress.hostname, showDivider = false)
    if (asked.isNotEmpty() && !SiteAddress.isValid(asked)) Note(stringResource(R.string.site_address_invalid), Gryonix.colors.warning)
    Note(stringResource(R.string.site_address_note), Gryonix.colors.secondaryLabel)
    ApplyPendingBar(
        visible = SiteAddress.isValid(asked) && asked != ingress.hostname,
        apply = stringResource(R.string.airplay_apply),
        cancel = stringResource(R.string.pending_changes_cancel),
        onApply = {
            val moved = deployment.copy(serviceSettings = slot.set(deployment.serviceSettings, asked))
            reapply(moved, service)
            tools.homeOnly?.dns?.let { dns ->
                scope.launch {
                    dns.change(HomeOnlyDNS.Action.RESTORE, service, moved)
                    dns.change(HomeOnlyDNS.Action.REMOVE, service, deployment)
                }
            }
            typed = ""
        },
        onRevert = { typed = "" },
    )
    if (!ingress.homeOnly && deployment.scope.publishesAddressRecords) {
        tools.homeOnly?.let { SiteDNSControls(service, deployment, it) }
    }
}

@Composable
private fun Note(text: String, color: androidx.compose.ui.graphics.Color) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = color, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
}
