package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.MenuCheckItem
import com.skaymer.gryonixnexus.app.ui.design.MenuHeader
import com.skaymer.gryonixnexus.app.ui.design.MenuValueRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.app.vpn.DNSSource
import com.skaymer.gryonixnexus.app.vpn.LocalDNS
import com.skaymer.gryonixnexus.app.vpn.PublicDNS

/** What this server's own resolver is called */
@Composable
fun localName(local: LocalDNS): String = serverDNSName(local.serviceNames)

@Composable
private fun serverDNSName(names: String?): String =
    names?.let { stringResource(R.string.dns_local_named, it) } ?: stringResource(R.string.dns_this_server)

/** A device's DNS, named by whose resolver it is */
@Composable
fun dnsName(addresses: List<String>, local: LocalDNS = LocalDNS()): String =
    when (val source = local.source(addresses)) {
        is DNSSource.YourServer -> serverDNSName(source.names)
        is DNSSource.Public -> stringResource(R.string.dns_public_named, presetName(source.preset))
        is DNSSource.Typed -> source.addresses.joinToString(", ")
    }

/** A public resolver's name, with its variant */
@Composable
fun presetName(preset: PublicDNS): String =
    preset.variant?.let { "${preset.provider} — ${stringResource(it)}" } ?: preset.provider

/** The DNS row; a tap opens the choice */
@Composable
fun DNSRow(
    addresses: List<String>,
    onChoose: (List<String>) -> Unit,
    local: LocalDNS = LocalDNS(),
    showDivider: Boolean = true,
) {
    var choosing by remember { mutableStateOf(false) }
    ValueRow(
        title = stringResource(R.string.dns_row),
        value = dnsName(addresses, local),
        onClick = { choosing = true },
        showDivider = showDivider,
    )
    if (choosing) {
        DNSPickerSheet(addresses, local = local, onChoose = { choosing = false; onChoose(it) }, onClose = { choosing = false })
    }
}

/** Public resolvers, this server's own, then typed addresses */
@Composable
fun DNSPickerSheet(
    current: List<String>,
    onChoose: (List<String>) -> Unit,
    onClose: () -> Unit,
    local: LocalDNS = LocalDNS(),
) {
    val chosen = PublicDNS.matching(current)
    val typedBefore = chosen == null && !local.isChosen(current)
    var typed by remember { mutableStateOf(if (typedBefore) current.joinToString(", ") else "") }
    val parsed = PublicDNS.parse(typed)
    IOSSheet(title = stringResource(R.string.dns_row), onClose = onClose, closeLabel = stringResource(R.string.vpn_cancel)) {
        if (local.isOffered) {
            LocalDNSSection(local, chosen = local.isChosen(current), onChoose = onChoose)
        }
        GroupedSection(header = stringResource(R.string.dns_public)) {
            PublicDNS.all.forEach { preset ->
                CheckRow(
                    title = presetName(preset),
                    subtitle = preset.addresses.take(2).joinToString(", "),
                    checked = preset.id == chosen?.id,
                    onClick = { onChoose(preset.addresses) },
                    showDivider = preset != PublicDNS.all.last(),
                )
            }
        }
        GroupedSection(header = stringResource(R.string.dns_own_title), note = stringResource(R.string.dns_own_hint)) {
            FieldRow(label = stringResource(R.string.dns_servers), value = typed, onValueChange = { typed = it })
            ActionRow(
                text = stringResource(R.string.dns_own),
                enabled = parsed != null,
                onClick = { parsed?.let(onChoose) },
                showDivider = false,
            )
        }
    }
}

/** The DNS row as a popup menu */
@Composable
fun DNSMenuRow(
    addresses: List<String>,
    local: LocalDNS,
    enabled: Boolean,
    onChoose: (List<String>) -> Unit,
) {
    var typing by remember { mutableStateOf(false) }
    MenuValueRow(stringResource(R.string.dns_row), dnsName(addresses, local), enabled) { close ->
        if (local.isOffered) {
            MenuHeader(stringResource(R.string.dns_on_your_server))
            MenuCheckItem(localName(local), local.isChosen(addresses)) { close(); onChoose(listOf(local.address)) }
        }
        MenuHeader(stringResource(R.string.dns_public))
        val chosen = PublicDNS.matching(addresses)
        PublicDNS.all.forEach { preset ->
            MenuCheckItem(presetName(preset), preset.id == chosen?.id) { close(); onChoose(preset.addresses) }
        }
        HorizontalDivider()
        DropdownMenuItem(
            text = { Text(stringResource(R.string.dns_other_addresses)) },
            onClick = { close(); typing = true },
        )
    }
    if (typing) {
        DNSPickerSheet(addresses, local = local, onChoose = { typing = false; onChoose(it) }, onClose = { typing = false })
    }
}

/** AdGuard Home or Pi-hole on this server */
@Composable
private fun LocalDNSSection(local: LocalDNS, chosen: Boolean, onChoose: (List<String>) -> Unit) {
    GroupedSection(header = stringResource(R.string.dns_on_your_server)) {
        CheckRow(
            title = localName(local),
            subtitle = local.address,
            checked = chosen,
            onClick = { onChoose(listOf(local.address)) },
            showDivider = false,
        )
    }
}

/** Public resolvers side by side */
@Composable
fun PublicDNSSheet(highlighted: PublicDNS?, onClose: () -> Unit) {
    IOSSheet(title = stringResource(R.string.dns_public), onClose = onClose, closeLabel = stringResource(R.string.close)) {
        highlighted?.let { preset ->
            GroupedSection(header = presetName(preset)) {
                GroupedRow(showDivider = false) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(stringResource(preset.summary), style = MaterialTheme.typography.bodyMedium)
                        Text(preset.addresses.joinToString("\n"), style = MaterialTheme.typography.bodySmall,
                            color = Gryonix.colors.secondaryLabel)
                    }
                }
            }
        }
        GroupedSection(header = stringResource(R.string.dns_comparison), note = stringResource(R.string.dns_compare_footer)) {
            ComparisonHeader()
            PublicDNS.all.forEach { row ->
                ComparisonRow(row, current = row.id == highlighted?.id, showDivider = row != PublicDNS.all.last())
            }
        }
    }
}

@Composable
private fun ComparisonHeader() {
    GroupedRow {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            val style = MaterialTheme.typography.labelSmall
            Text(stringResource(R.string.dns_col_service), style = style, modifier = Modifier.weight(1.4f))
            Text(stringResource(R.string.dns_col_speed), style = style, modifier = Modifier.width(52.dp))
            Text(stringResource(R.string.dns_col_privacy), style = style, modifier = Modifier.width(60.dp))
            Text(stringResource(R.string.dns_col_blocks), style = style, modifier = Modifier.weight(1f))
        }
    }
}

@Composable
private fun ComparisonRow(row: PublicDNS, current: Boolean, showDivider: Boolean) {
    GroupedRow(showDivider = showDivider) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                presetName(row),
                style = MaterialTheme.typography.bodySmall,
                fontWeight = if (current) FontWeight.SemiBold else FontWeight.Normal,
                modifier = Modifier.weight(1.4f),
            )
            Box(Modifier.width(52.dp)) { RatingDots(row.speed) }
            Box(Modifier.width(60.dp)) { RatingDots(row.privacy) }
            Text(stringResource(row.blocks), style = MaterialTheme.typography.labelSmall,
                color = Gryonix.colors.secondaryLabel, modifier = Modifier.weight(1f))
        }
    }
}

/** "●●○", language-independent by design */
@Composable
private fun RatingDots(value: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        repeat(3) { index ->
            Box(
                Modifier.size(7.dp).background(
                    if (index < value) Gryonix.colors.accent else Gryonix.colors.tertiaryLabel.copy(alpha = 0.3f),
                    CircleShape,
                ),
            )
        }
    }
}
