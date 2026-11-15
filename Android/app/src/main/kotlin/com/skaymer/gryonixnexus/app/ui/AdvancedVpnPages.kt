package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.RowScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import com.skaymer.gryonixnexus.profile.advanced.AdvancedGroup
import com.skaymer.gryonixnexus.profile.advanced.AdvancedRule
import com.skaymer.gryonixnexus.profile.advanced.GroupMode
import com.skaymer.gryonixnexus.profile.advanced.RuleAction
import com.skaymer.gryonixnexus.profile.advanced.RuleKind
import kotlinx.coroutines.launch

@Composable
internal fun AdvancedActionPicker(title: String, selected: RuleAction, onSelect: (RuleAction) -> Unit) {
    GroupedRow {
        RowLabel(title)
        IOSSegmentedControl(
            segments = RuleAction.entries,
            selected = selected,
            label = { stringResource(actionText(it)) },
            onSelect = onSelect,
        )
    }
}

internal fun DeleteButton(onClick: () -> Unit): @Composable RowScope.() -> Unit = {
    IconButton(onClick = onClick) { Icon(Icons.Filled.Delete, contentDescription = null) }
}

@Composable
internal fun AdvancedImportPage(store: AdvancedVpnStore) {
    val profile by store.profile.collectAsState()
    val report by store.report.collectAsState()
    val busy by store.busy.collectAsState()
    val scope = rememberCoroutineScope()
    var address by rememberSaveable { mutableStateOf("") }
    var pasted by rememberSaveable { mutableStateOf("") }
    Column(verticalArrangement = GroupedSpacing) {
        GroupedSection(header = stringResource(R.string.adv_subscriptions), note = stringResource(R.string.adv_subscriptions_note)) {
            profile.subscriptions.forEach { subscription ->
                GroupedRow(trailing = DeleteButton {
                    store.update { p ->
                        p.removing(subscription.serverIDs.toSet())
                            .copy(subscriptions = p.subscriptions.filter { it.id != subscription.id })
                    }
                }) {
                    RowLabel(subscription.name, stringResource(R.string.adv_n_servers, subscription.serverIDs.size))
                }
                ActionRow(stringResource(R.string.adv_refresh), onClick = { scope.launch { store.refresh(subscription.id) } })
            }
            FieldRow(label = "https://", value = address, onValueChange = { address = it })
            ActionRow(
                stringResource(R.string.adv_add_subscription),
                enabled = address.isNotBlank() && !busy,
                showDivider = false,
                onClick = { scope.launch { store.addSubscription(address); address = "" } },
            )
        }
        GroupedSection(header = stringResource(R.string.adv_paste_header), note = stringResource(R.string.adv_paste_note)) {
            FieldRow(label = stringResource(R.string.adv_import), value = pasted, onValueChange = { pasted = it }, singleLine = false)
            ActionRow(
                stringResource(R.string.adv_import),
                enabled = pasted.isNotBlank(),
                showDivider = false,
                onClick = { store.importText(pasted); pasted = "" },
            )
        }
        report?.let { found ->
            GroupedSection(header = stringResource(R.string.adv_import_report)) {
                GroupedRow(showDivider = found.unsupported.isNotEmpty()) {
                    RowLabel(stringResource(R.string.adv_report_counts, found.servers.size, found.rules.size))
                }
                found.unsupported.forEachIndexed { index, skipped ->
                    GroupedRow(showDivider = index != found.unsupported.lastIndex) { RowLabel(skipped.name, skipped.reason) }
                }
            }
        }
    }
}

@Composable
internal fun AdvancedServersPage(store: AdvancedVpnStore) {
    val profile by store.profile.collectAsState()
    GroupedSection {
        if (profile.servers.isEmpty()) GroupedRow(showDivider = false) { RowLabel(stringResource(R.string.adv_no_servers)) }
        profile.servers.forEachIndexed { index, server ->
            GroupedRow(showDivider = index != profile.servers.lastIndex,
                trailing = DeleteButton { store.update { it.removing(setOf(server.id)) } }) {
                RowLabel(server.name, "${server.kind.name.lowercase()} · ${server.host}:${server.port}")
            }
        }
    }
}

@Composable
internal fun AdvancedGroupsPage(store: AdvancedVpnStore) {
    val profile by store.profile.collectAsState()
    var name by rememberSaveable { mutableStateOf("") }
    var auto by rememberSaveable { mutableStateOf(true) }
    var members by remember { mutableStateOf(setOf<String>()) }
    Column(verticalArrangement = GroupedSpacing) {
        if (profile.groups.isNotEmpty()) GroupedSection {
            profile.groups.forEachIndexed { index, group ->
                GroupedRow(showDivider = index != profile.groups.lastIndex, trailing = DeleteButton {
                    store.update { p ->
                        p.copy(groups = p.groups.filter { it.id != group.id },
                            activeID = p.activeID.takeIf { it != group.id })
                    }
                }) {
                    RowLabel(group.name, stringResource(if (group.mode == GroupMode.AUTO) R.string.adv_auto_lowest_ping else R.string.adv_manual))
                }
            }
        }
        GroupedSection(header = stringResource(R.string.adv_new_group)) {
            FieldRow(label = stringResource(R.string.adv_name), value = name, onValueChange = { name = it })
            GroupedRow {
                IOSSegmentedControl(
                    segments = listOf(true, false),
                    selected = auto,
                    label = { stringResource(if (it) R.string.adv_auto_lowest_ping else R.string.adv_manual) },
                    onSelect = { auto = it },
                )
            }
            profile.servers.forEach { server ->
                ToggleRow(server.name, checked = server.id in members,
                    onCheckedChange = { on -> members = if (on) members + server.id else members - server.id })
            }
            ActionRow(
                stringResource(R.string.adv_add_group),
                enabled = name.isNotBlank() && members.isNotEmpty(),
                showDivider = false,
                onClick = {
                    val ordered = profile.servers.map { it.id }.filter { it in members }
                    val mode = if (auto) GroupMode.AUTO else GroupMode.MANUAL
                    store.update { it.copy(groups = it.groups + AdvancedGroup(name = name, mode = mode, memberIDs = ordered)) }
                    name = ""
                    members = emptySet()
                },
            )
        }
    }
}

@Composable
internal fun AdvancedRulesPage(store: AdvancedVpnStore) {
    val profile by store.profile.collectAsState()
    var kind by rememberSaveable { mutableStateOf(RuleKind.DOMAIN_SUFFIX) }
    var value by rememberSaveable { mutableStateOf("") }
    var action by rememberSaveable { mutableStateOf(RuleAction.DIRECT) }
    val scope = rememberCoroutineScope()
    Column(verticalArrangement = GroupedSpacing) {
        GroupedSection(header = stringResource(R.string.adv_rules_in_order), note = stringResource(R.string.adv_rules_note)) {
            profile.rules.forEachIndexed { index, rule ->
                GroupedRow(showDivider = index != profile.rules.lastIndex, trailing = DeleteButton {
                    store.update { p -> p.copy(rules = p.rules.filter { it.id != rule.id }) }
                }) {
                    RowLabel(rule.value, stringResource(kindText(rule.kind)) + " · " + stringResource(actionText(rule.action)))
                }
            }
        }
        GroupedSection(header = stringResource(R.string.adv_new_rule)) {
            GroupedRow {
                IOSSegmentedControl(RuleKind.entries, kind, label = { stringResource(kindText(it)) }, onSelect = { kind = it })
            }
            FieldRow(label = stringResource(R.string.adv_value), value = value, onValueChange = { value = it })
            AdvancedActionPicker(stringResource(R.string.adv_action), action) { action = it }
            ActionRow(
                stringResource(R.string.adv_add_rule),
                enabled = value.isNotBlank(),
                showDivider = false,
                onClick = {
                    store.update { it.copy(rules = it.rules + AdvancedRule(kind, value.trim(), action)) }
                    value = ""
                    if (store.missingCountries.isNotEmpty()) scope.launch { store.refreshGeoIP() }
                },
            )
        }
        AdvancedGeoIpSection(store)
    }
}

private fun kindText(kind: RuleKind): Int = when (kind) {
    RuleKind.DOMAIN -> R.string.adv_kind_domain
    RuleKind.DOMAIN_SUFFIX -> R.string.adv_kind_suffix
    RuleKind.KEYWORD -> R.string.adv_kind_keyword
    RuleKind.IP -> R.string.adv_kind_ip
    RuleKind.GEOIP -> R.string.adv_kind_geoip
}
