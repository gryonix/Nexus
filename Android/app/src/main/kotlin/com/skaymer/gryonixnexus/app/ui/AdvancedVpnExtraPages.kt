package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
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
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.vpn.AdvancedVpnStore
import com.skaymer.gryonixnexus.profile.advanced.AdvancedGeoIP
import com.skaymer.gryonixnexus.profile.advanced.AdvancedHostRewrite
import kotlinx.coroutines.launch

/** Where country networks come from, and their state. */
@Composable
internal fun AdvancedGeoIpSection(store: AdvancedVpnStore) {
    val profile by store.profile.collectAsState()
    val busy by store.busy.collectAsState()
    val scope = rememberCoroutineScope()
    val status = if (profile.geoip.updatedAtMillis == null) stringResource(R.string.adv_geoip_none)
    else stringResource(R.string.adv_geoip_count, profile.geoip.ranges.size)
    GroupedSection(header = stringResource(R.string.adv_geoip_title), note = stringResource(R.string.adv_geoip_note)) {
        FieldRow(label = "https://", value = profile.geoip.url, onValueChange = { text ->
            store.update { it.copy(geoip = it.geoip.copy(url = text.trim())) }
        })
        GroupedRow { RowLabel(status) }
        ActionRow(
            stringResource(R.string.adv_refresh),
            enabled = !busy && AdvancedGeoIP.codes(profile.rules).isNotEmpty(),
            showDivider = false,
            onClick = { scope.launch { store.refreshGeoIP() } },
        )
    }
}

/** Domains answered with a chosen address, off by default. */
@Composable
internal fun AdvancedRewritesPage(store: AdvancedVpnStore) {
    val profile by store.profile.collectAsState()
    var domain by rememberSaveable { mutableStateOf("") }
    var target by rememberSaveable { mutableStateOf("") }
    Column(verticalArrangement = GroupedSpacing) {
        GroupedSection(header = stringResource(R.string.adv_rewrites_title), note = stringResource(R.string.adv_rewrites_note)) {
            ToggleRow(stringResource(R.string.adv_rewrites_use), checked = profile.rewritesEnabled,
                onCheckedChange = { on -> store.update { it.copy(rewritesEnabled = on) } }, showDivider = false)
        }
        GroupedSection {
            profile.hosts.forEachIndexed { index, rewrite ->
                GroupedRow(showDivider = index != profile.hosts.lastIndex, trailing = DeleteButton {
                    store.update { p -> p.copy(hosts = p.hosts.filter { it.id != rewrite.id }) }
                }) { RowLabel(rewrite.domain, "→ ${rewrite.target}") }
            }
        }
        GroupedSection {
            FieldRow(label = stringResource(R.string.adv_kind_domain), value = domain, onValueChange = { domain = it })
            FieldRow(label = stringResource(R.string.adv_rewrite_target), value = target, onValueChange = { target = it })
            ActionRow(
                stringResource(R.string.adv_add_rewrite),
                enabled = domain.isNotBlank() && target.isNotBlank(),
                showDivider = false,
                onClick = {
                    store.update { it.copy(hosts = it.hosts + AdvancedHostRewrite(domain.trim(), target.trim())) }
                    domain = ""
                    target = ""
                },
            )
        }
    }
}
