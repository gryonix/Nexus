package com.skaymer.gryonixnexus.app.ui

import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.core.net.toUri
import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.servers.HomeDoors
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.WebSite
import com.skaymer.gryonixnexus.app.servers.WebSites
import com.skaymer.gryonixnexus.app.shell.TabBarSettings
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** Where the services of this server actually live, as links */
@Composable
fun SitesCard(deployment: Deployment, tabs: TabBarSettings) {
    val context = LocalContext.current
    val collapsible by tabs.sitesCollapsible.collectAsState()
    val serviceContext = remember(deployment) { deployment.serviceContext }
    val sites = remember(deployment) { WebSites.of(deployment.services, serviceContext) }
    val needDomain = remember(deployment) {
        WebSites.needDomain(deployment.services, serviceContext)
    }
    if (sites.isEmpty() && !needDomain) return

    var folded by rememberSaveable(deployment.id) { mutableStateOf(false) }
    val expanded = remember(collapsible, folded) { tabs.sitesPlateExpanded(folded) }

    val homeDoors = (context.applicationContext as GryonixApplication).homeDoors
    val doors by homeDoors.doors.collectAsState()
    LaunchedEffect(deployment.id) { homeDoors.load(deployment) }
    val atHome = doors[deployment.id.toString()].orEmpty()
    val meshAddresses by homeDoors.mesh.collectAsState()
    val meshAddress = meshAddresses[deployment.id.toString()]
    val homeOnly = sites.any { it.host.lowercase().endsWith(".local") }
    GroupedSection(
        header = stringResource(R.string.sites_title),
        footer = if (homeOnly) stringResource(R.string.sites_home_only) else null,
    ) {
        if (collapsible) GroupedRow(
            onClick = { folded = !folded },
            showDivider = expanded,
            trailing = {
                // Folded, the count is the only thing left to read.
                if (sites.isNotEmpty()) {
                    Text(
                        sites.size.toString(),
                        style = MaterialTheme.typography.bodyLarge,
                        color = Gryonix.colors.secondaryLabel,
                    )
                }
                Icon(
                    if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                    contentDescription = null,
                    tint = Gryonix.colors.accent,
                    modifier = Modifier.size(20.dp),
                )
            },
        ) {
            Text(
                stringResource(R.string.sites_title),
                style = MaterialTheme.typography.bodyLarge,
                color = Gryonix.colors.label,
                modifier = Modifier.weight(1f),
            )
        }
        if (!expanded) return@GroupedSection
        if (sites.isEmpty()) {
            GroupedRow(showDivider = false) {
                Text(
                    stringResource(R.string.sites_no_domain),
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
            return@GroupedSection
        }
        sites.forEach { site ->
            val port = atHome[site.id.rawValue]
            SiteRow(site, showDivider = port != null || site != sites.last())
            if (port != null) {
                HomeDoorRow(stringResource(R.string.sites_home_apps), HomeDoors.url(deployment, port), showDivider = true)
                meshAddress?.let {
                    HomeDoorRow(stringResource(R.string.sites_home_vpn), HomeDoors.meshURL(it, port), showDivider = true)
                }
                UnencryptedDoorNote(showDivider = site != sites.last())
            }
        }
    }
}

/** The plain address phone and desktop apps use at home */
@Composable
private fun HomeDoorRow(label: String, address: String, showDivider: Boolean) {
    val clipboard = LocalClipboardManager.current
    var copied by remember(address) { mutableStateOf(false) }
    GroupedRow(
        onClick = {
            clipboard.setText(AnnotatedString(address))
            copied = true
        },
        showDivider = showDivider,
        trailing = {
            Icon(
                if (copied) Icons.Filled.Check else Icons.Filled.ContentCopy,
                contentDescription = stringResource(R.string.sites_home_copy),
                tint = Gryonix.colors.accent,
                modifier = Modifier.size(18.dp),
            )
        },
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                label,
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.secondaryLabel,
            )
            Text(
                address,
                style = MaterialTheme.typography.bodyMedium,
                fontFamily = FontFamily.Monospace,
                color = Gryonix.colors.label,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun SiteRow(site: WebSite, showDivider: Boolean) {
    val context = LocalContext.current
    GroupedRow(
        onClick = {
            val intent = Intent(Intent.ACTION_VIEW, site.url.toUri())
            try {
                context.startActivity(intent)
            } catch (_: ActivityNotFoundException) {
            }
        },
        showDivider = showDivider,
        trailing = {
            Icon(
                Icons.Filled.OpenInNew,
                contentDescription = null,
                tint = Gryonix.colors.tertiaryLabel,
                modifier = Modifier.size(18.dp),
            )
        },
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                site.name,
                style = MaterialTheme.typography.bodyLarge,
                color = Gryonix.colors.label,
            )
            Text(
                site.host,
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.secondaryLabel,
                maxLines = 1,
                overflow = TextOverflow.MiddleEllipsis,
            )
        }
    }
}

/** Says the plain address carries no encryption */
@Composable
private fun UnencryptedDoorNote(showDivider: Boolean) {
    GroupedRow(showDivider = showDivider) {
        Text(
            stringResource(R.string.sites_home_unencrypted),
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.warning,
        )
    }
}
