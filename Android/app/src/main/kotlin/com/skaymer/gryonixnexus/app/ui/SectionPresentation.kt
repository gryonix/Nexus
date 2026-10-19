package com.skaymer.gryonixnexus.app.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material.icons.filled.Tune
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.vectorResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.shell.AppTab
import com.skaymer.gryonixnexus.app.shell.ServerSection
import com.skaymer.gryonixnexus.app.vpn.VpnTunnel

/** How a section is drawn */
val AppTab.titleRes: Int
    get() = when (this) {
        AppTab.SERVERS -> R.string.tab_servers
        AppTab.METRICS -> R.string.tab_metrics
        AppTab.CONTAINERS -> R.string.tab_containers
        AppTab.VPN -> R.string.tab_vpn
        AppTab.TERMINAL -> R.string.tab_terminal
        AppTab.CONFIGURATOR -> R.string.tab_configurator
        AppTab.SETTINGS -> R.string.tab_settings
    }

val AppTab.icon: ImageVector
    @Composable get() = when (this) {
        AppTab.SERVERS -> Icons.Filled.Dns
        AppTab.METRICS -> Icons.Filled.BarChart
        AppTab.CONTAINERS -> Icons.Filled.Inventory2
        AppTab.VPN -> ImageVector.vectorResource(R.drawable.tab_icon_logo)
        AppTab.TERMINAL -> Icons.Filled.Terminal
        AppTab.CONFIGURATOR -> Icons.Filled.Tune
        AppTab.SETTINGS -> Icons.Filled.Settings
    }

@Composable
fun AppTab.icon(tunnelActive: Boolean): ImageVector = when (this) {
    AppTab.VPN -> ImageVector.vectorResource(vpnMarkRes(tunnelActive))
    else -> icon
}

fun vpnMarkRes(tunnelActive: Boolean): Int =
    if (tunnelActive) R.drawable.tab_icon_logo else R.drawable.tab_icon_globe

/** Whether the tunnel counts as up for the mark above */
fun VpnTunnel.State.carriesASession(): Boolean = when (this) {
    is VpnTunnel.State.Up, is VpnTunnel.State.Working -> true
    is VpnTunnel.State.Down, is VpnTunnel.State.Failed -> false
}

/** The same split for a server's own sections — see `ServerSection` */
val ServerSection.titleRes: Int
    get() = when (this) {
        ServerSection.GENERAL -> R.string.section_general
        ServerSection.APPS -> R.string.section_apps
        ServerSection.METRICS -> R.string.tab_metrics
        ServerSection.CONTAINERS -> R.string.tab_containers
        ServerSection.VPN -> R.string.tab_vpn
        ServerSection.TERMINAL -> R.string.tab_terminal
    }
