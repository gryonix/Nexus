package com.skaymer.gryonixnexus.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.vpn.AdvancedVpnStore
import com.skaymer.gryonixnexus.profile.advanced.RuleAction

/** The parts of the advanced VPN screen. */
enum class AdvancedPage { ROOT, IMPORT, SERVERS, GROUPS, RULES, DNS, BLOCK_LISTS, REWRITES, TRAFFIC }

@Composable
fun AdvancedVpnScreen(store: AdvancedVpnStore, onApply: (String) -> Unit, onClose: () -> Unit) {
    var page by rememberSaveable { mutableStateOf(AdvancedPage.ROOT) }
    BackHandler { if (page == AdvancedPage.ROOT) onClose() else page = AdvancedPage.ROOT }
    LaunchedEffect(Unit) { store.refreshDue() }
    LazyColumn(
        modifier = Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        when (page) {
            AdvancedPage.ROOT -> item { AdvancedRoot(store, onApply) { page = it } }
            AdvancedPage.IMPORT -> item { AdvancedImportPage(store) }
            AdvancedPage.SERVERS -> item { AdvancedServersPage(store) }
            AdvancedPage.GROUPS -> item { AdvancedGroupsPage(store) }
            AdvancedPage.RULES -> item { AdvancedRulesPage(store) }
            AdvancedPage.DNS -> item { AdvancedDnsPage(store) }
            AdvancedPage.BLOCK_LISTS -> item { AdvancedBlockListsPage(store) }
            AdvancedPage.REWRITES -> item { AdvancedRewritesPage(store) }
            AdvancedPage.TRAFFIC -> item { AdvancedTrafficPage(store) }
        }
    }
}

@Composable
private fun AdvancedRoot(store: AdvancedVpnStore, onApply: (String) -> Unit, open: (AdvancedPage) -> Unit) {
    val profile by store.profile.collectAsState()
    val notice by store.notice.collectAsState()
    androidx.compose.foundation.layout.Column(verticalArrangement = GroupedSpacing) {
        GroupedSection(header = stringResource(R.string.adv_runs), note = stringResource(R.string.adv_apply_note)) {
            val targets = profile.groups.map { it.id to it.name } + profile.servers.map { it.id to it.name }
            targets.forEachIndexed { index, (id, name) ->
                CheckRow(name, checked = profile.activeID == id, showDivider = true,
                    onClick = { store.update { it.copy(activeID = id) } })
            }
            AdvancedActionPicker(stringResource(R.string.adv_everything_else), profile.finalAction) { action ->
                store.update { it.copy(finalAction = action) }
            }
            ActionRow(
                text = stringResource(R.string.adv_apply),
                enabled = profile.servers.isNotEmpty(),
                showDivider = false,
                onClick = { store.tunnelText()?.let(onApply) },
            )
        }
        GroupedSection {
            val pages = listOf(
                AdvancedPage.IMPORT to stringResource(R.string.adv_import),
                AdvancedPage.SERVERS to stringResource(R.string.adv_servers, profile.servers.size),
                AdvancedPage.GROUPS to stringResource(R.string.adv_groups, profile.groups.size),
                AdvancedPage.RULES to stringResource(R.string.adv_rules, profile.rules.size),
                AdvancedPage.DNS to stringResource(R.string.adv_dns),
                AdvancedPage.BLOCK_LISTS to stringResource(R.string.adv_block_lists, profile.blockLists.size),
                AdvancedPage.REWRITES to stringResource(R.string.adv_rewrites, profile.hosts.size),
                AdvancedPage.TRAFFIC to stringResource(R.string.adv_traffic),
            )
            pages.forEachIndexed { index, (target, title) ->
                GroupedRow(showDivider = index != pages.lastIndex, onClick = { open(target) },
                    trailing = { DisclosureChevron() }) { RowLabel(title) }
            }
        }
        notice?.let { GroupedSection { GroupedRow(showDivider = false) { RowLabel(stringResource(noticeText(it))) } } }
    }
}

internal fun noticeText(notice: AdvancedVpnStore.Notice): Int = when (notice) {
    AdvancedVpnStore.Notice.NEED_HTTPS -> R.string.adv_need_https
    AdvancedVpnStore.Notice.SUBSCRIPTION_FAILED -> R.string.adv_sub_failed
    AdvancedVpnStore.Notice.LIST_FAILED -> R.string.adv_list_failed
    AdvancedVpnStore.Notice.CHOOSE_FIRST -> R.string.adv_choose_first
    AdvancedVpnStore.Notice.GEOIP_FAILED -> R.string.adv_geoip_failed
}

internal fun actionText(action: RuleAction): Int = when (action) {
    RuleAction.DIRECT -> R.string.adv_direct
    RuleAction.PROXY -> R.string.adv_proxy
    RuleAction.BLOCK -> R.string.adv_block
}
