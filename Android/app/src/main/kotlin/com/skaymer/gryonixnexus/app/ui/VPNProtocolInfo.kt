package com.skaymer.gryonixnexus.app.ui

import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.GppGood
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet

/** What one VPN protocol is good at, as on iOS */
data class VPNProtocolInfo(
    val serviceID: ServiceID,
    @StringRes val summary: Int,
    val speed: Int,
    val stealth: Int,
    val simplicity: Int,
) {
    /** Whether this protocol carries traffic to the admin panels */
    val reachesAdminPanels: Boolean get() = serviceID == ServiceID.WIREGUARD_VPN

    companion object {
        val all = listOf(
            VPNProtocolInfo(ServiceID.WIREGUARD_VPN, R.string.vpn_info_wireguard, 3, 1, 3),
            VPNProtocolInfo(ServiceID.AMNEZIA_WG, R.string.vpn_info_amnezia, 3, 2, 3),
            VPNProtocolInfo(ServiceID.SHADOWSOCKS, R.string.vpn_info_shadowsocks, 3, 2, 2),
            VPNProtocolInfo(ServiceID.XRAY_REALITY, R.string.vpn_info_reality, 2, 3, 1),
            VPNProtocolInfo(ServiceID.OPEN_VPN, R.string.vpn_info_openvpn, 1, 1, 2),
        )

        fun of(id: ServiceID): VPNProtocolInfo? = all.firstOrNull { it.serviceID == id }
    }
}

private fun nameOf(id: ServiceID): String = ServiceRegistry.service(id)?.displayName ?: id.rawValue

/** Advantages, admin panels and the comparison of every protocol */
@Composable
fun VPNProtocolInfoSheet(info: VPNProtocolInfo, onClose: () -> Unit) {
    IOSSheet(title = nameOf(info.serviceID), onClose = onClose, closeLabel = stringResource(R.string.vpn_info_done)) {
        GroupedSection(header = stringResource(R.string.vpn_info_advantages)) {
            GroupedRow(showDivider = false) {
                Text(stringResource(info.summary), style = MaterialTheme.typography.bodyMedium, color = Gryonix.colors.label)
            }
        }
        GroupedSection(header = stringResource(R.string.vpn_info_panels)) {
            GroupedRow(
                showDivider = false,
                leading = {
                    Icon(
                        if (info.reachesAdminPanels) Icons.Outlined.GppGood else Icons.Outlined.Lock, null,
                        tint = if (info.reachesAdminPanels) Gryonix.colors.success else Gryonix.colors.warning,
                    )
                },
            ) {
                Text(
                    stringResource(if (info.reachesAdminPanels) R.string.vpn_info_panels_yes else R.string.vpn_info_panels_no),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.label,
                    modifier = Modifier.weight(1f),
                )
            }
        }
        GroupedSection(header = stringResource(R.string.vpn_info_comparison)) { ComparisonRows(info) }
    }
}

@Composable
private fun ComparisonRows(shown: VPNProtocolInfo) {
    GroupedRow {
        ComparisonCells(
            stringResource(R.string.vpn_pick_protocol),
            listOf(R.string.vpn_info_speed, R.string.vpn_info_stealth, R.string.vpn_info_ease).map { stringResource(it) },
        )
    }
    VPNProtocolInfo.all.forEach { row ->
        GroupedRow(showDivider = row != VPNProtocolInfo.all.last()) {
            Text(
                nameOf(row.serviceID),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = if (row == shown) FontWeight.SemiBold else FontWeight.Normal,
                color = if (row == shown) Gryonix.colors.label else Gryonix.colors.secondaryLabel,
                maxLines = 1,
                modifier = Modifier.weight(1f),
            )
            listOf(row.speed, row.stealth, row.simplicity).forEach { Dots(it) }
        }
    }
}

@Composable
private fun RowScope.ComparisonCells(first: String, rest: List<String>) {
    Text(first, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold,
        color = Gryonix.colors.secondaryLabel, modifier = Modifier.weight(1f))
    rest.forEach {
        Text(it, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold,
            color = Gryonix.colors.secondaryLabel, maxLines = 1, modifier = Modifier.width(CELL))
    }
}

private val CELL = 64.dp

/** "●●○", the same in every language */
@Composable
private fun Dots(value: Int) {
    Row(Modifier.width(CELL), horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
        repeat(3) { index ->
            Box(
                Modifier.size(7.dp).background(
                    if (index < value) Gryonix.colors.accent else Gryonix.colors.tertiaryLabel.copy(alpha = 0.4f),
                    CircleShape,
                ),
            )
        }
    }
}
