package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.vpn.AdvancedVpnStore
import com.skaymer.gryonixnexus.profile.advanced.AdvancedDnsUpstream
import com.skaymer.gryonixnexus.profile.advanced.DnsKind
import kotlinx.coroutines.launch

@Composable
internal fun AdvancedDnsPage(store: AdvancedVpnStore) {
    val profile by store.profile.collectAsState()
    var kind by rememberSaveable { mutableStateOf(DnsKind.DOH) }
    var address by rememberSaveable { mutableStateOf("") }
    var domains by rememberSaveable { mutableStateOf("") }
    var viaProxy by rememberSaveable { mutableStateOf(true) }
    Column(verticalArrangement = GroupedSpacing) {
        GroupedSection(header = stringResource(R.string.adv_upstreams), note = stringResource(R.string.adv_dns_note)) {
            profile.dns.forEachIndexed { index, upstream ->
                GroupedRow(showDivider = index != profile.dns.lastIndex, trailing = {
                    IconButton(onClick = { store.update { p -> p.copy(dns = p.dns.filter { it.id != upstream.id }) } }) {
                        Icon(Icons.Filled.Delete, contentDescription = null)
                    }
                }) {
                    RowLabel(upstream.address, (listOf(upstream.kind.name) + upstream.domains).joinToString(" · "))
                }
            }
        }
        GroupedSection(header = stringResource(R.string.adv_new_upstream)) {
            GroupedRow { IOSSegmentedControl(DnsKind.entries, kind, label = { it.name }, onSelect = { kind = it }) }
            FieldRow(label = stringResource(R.string.adv_address), value = address, onValueChange = { address = it })
            FieldRow(label = stringResource(R.string.adv_only_domains), value = domains, onValueChange = { domains = it })
            ToggleRow(stringResource(R.string.adv_via_proxy), checked = viaProxy, onCheckedChange = { viaProxy = it },
                enabled = kind == DnsKind.DOH || kind == DnsKind.TCP || kind == DnsKind.DOT)
            ActionRow(
                stringResource(R.string.adv_add_upstream),
                enabled = address.isNotBlank(),
                showDivider = false,
                onClick = {
                    val list = domains.split(',').map { it.trim() }.filter { it.isNotEmpty() }
                    store.update { it.copy(dns = it.dns + AdvancedDnsUpstream(kind, address.trim(), list, viaProxy)) }
                    address = ""
                    domains = ""
                },
            )
        }
    }
}

@Composable
internal fun AdvancedBlockListsPage(store: AdvancedVpnStore) {
    val profile by store.profile.collectAsState()
    val busy by store.busy.collectAsState()
    val scope = rememberCoroutineScope()
    var address by rememberSaveable { mutableStateOf("") }
    Column(verticalArrangement = GroupedSpacing) {
        GroupedSection(header = stringResource(R.string.adv_block_lists_title), note = stringResource(R.string.adv_block_note)) {
            profile.blockLists.forEach { list ->
                GroupedRow(trailing = {
                    IconButton(onClick = { store.update { p -> p.copy(blockLists = p.blockLists.filter { it.id != list.id }) } }) {
                        Icon(Icons.Filled.Delete, contentDescription = null)
                    }
                }) { RowLabel(list.url, stringResource(R.string.adv_domains_count, list.domains.size)) }
                ActionRow(stringResource(R.string.adv_refresh), onClick = { scope.launch { store.refreshBlockList(list.id) } })
            }
            FieldRow(label = "https://", value = address, onValueChange = { address = it })
            ActionRow(
                stringResource(R.string.adv_add_list),
                enabled = address.isNotBlank() && !busy,
                showDivider = false,
                onClick = { scope.launch { store.addBlockList(address); address = "" } },
            )
        }
    }
}

@Composable
internal fun AdvancedTrafficPage(store: AdvancedVpnStore) {
    val profile by store.profile.collectAsState()
    val traffic by store.traffic.collectAsState()
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { store.refreshTraffic() }
    Column(verticalArrangement = GroupedSpacing) {
        GroupedSection(footer = stringResource(R.string.adv_collect_note)) {
            ToggleRow(stringResource(R.string.adv_collect), checked = profile.collectsTraffic,
                onCheckedChange = { on -> store.update { it.copy(collectsTraffic = on) } }, showDivider = false)
        }
        traffic?.let { current ->
            GroupedSection(header = stringResource(R.string.adv_this_session)) {
                GroupedRow { RowLabel(stringResource(R.string.adv_through_vpn), formatBytes(current.proxy.total)) }
                GroupedRow(showDivider = false) { RowLabel(stringResource(R.string.adv_direct), formatBytes(current.direct.total)) }
            }
            GroupedSection(header = stringResource(R.string.adv_recent)) {
                current.requests.asReversed().forEachIndexed { index, request ->
                    GroupedRow(showDivider = index != current.requests.lastIndex) { RowLabel(request.domain, request.route) }
                }
            }
        }
        GroupedSection { ActionRow(stringResource(R.string.adv_update), showDivider = false, onClick = { scope.launch { store.refreshTraffic() } }) }
    }
}

private fun formatBytes(bytes: Long): String = "%.1f MB".format(bytes / 1_000_000.0)
