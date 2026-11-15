package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Apps
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.OpenAPIState
import com.skaymer.gryonixnexus.app.servers.OpenAPIViewModel
import com.skaymer.gryonixnexus.app.ui.design.ApplyPendingBar
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.IOSSwitch
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.catalog.ServiceAPIGroups
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** The translated words of a catalog group */
@Composable
private fun groupText(text: String): String = when (text) {
    "Bitwarden apps" -> stringResource(R.string.api_group_bitwarden)
    "Mail apps" -> stringResource(R.string.api_group_mail)
    "Webhooks" -> stringResource(R.string.api_group_webhooks)
    "Nextcloud apps" -> stringResource(R.string.api_group_nextcloud)
    "Immich app" -> stringResource(R.string.api_group_immich)
    "Seafile apps" -> stringResource(R.string.api_group_seafile)
    "API" -> stringResource(R.string.api_group_api)
    "Phone, desktop and browser apps sync your passwords." -> stringResource(R.string.api_group_bitwarden_detail)
    "Calendars, contacts and ActiveSync in mail apps." -> stringResource(R.string.api_group_mail_detail)
    "Other services start your workflows." -> stringResource(R.string.api_group_webhooks_detail)
    "Files, calendars and contacts in the apps. Sign in once over the VPN." -> stringResource(R.string.api_group_nextcloud_detail)
    "Photo backup from the phone." -> stringResource(R.string.api_group_immich_detail)
    "Sync clients and the mobile app." -> stringResource(R.string.api_group_seafile_detail)
    "Programs that call your models with a key." -> stringResource(R.string.api_group_api_detail)
    else -> text
}

/** The switches of one service's API groups */
@Composable
fun OpenAPIGroupsSection(deployment: Deployment, id: ServiceID, model: OpenAPIViewModel, siteGuarded: Boolean?) {
    val state by model.state.collectAsState()
    val groups = ServiceAPIGroups.groups(id)
    var draft by remember(deployment.id, id, state.site(id)?.paths) { mutableStateOf(emptyMap<String, Boolean>()) }
    val waiting = draft.filter { (group, open) -> groups.firstOrNull { it.id == group }?.let { state.isOpen(it, id) } != open }
    GroupedSection(
        header = stringResource(R.string.api_without_vpn),
        note = stringResource(R.string.api_without_vpn_note),
        onRefresh = { model.refresh(deployment) },
        refreshDescription = stringResource(R.string.refresh_this_again),
        refreshing = state.loading || id in state.busy,
        footer = note(state, id, siteGuarded),
    ) {
        groups.forEach { group ->
            GroupedRow(
                showDivider = group != groups.last(),
                trailing = {
                    IOSSwitch(
                        checked = draft[group.id] ?: state.isOpen(group, id),
                        enabled = state.canChange(id),
                        onCheckedChange = { draft = draft + (group.id to it) },
                    )
                },
            ) { RowLabel(groupText(group.title), groupText(group.detail)) }
        }
    }
    ApplyPendingBar(
        visible = waiting.isNotEmpty(),
        apply = stringResource(R.string.airplay_apply),
        cancel = stringResource(R.string.pending_changes_cancel),
        onApply = { model.setGroups(deployment, id, waiting); draft = emptyMap() },
        onRevert = { draft = emptyMap() },
    )
}

@Composable
private fun note(state: OpenAPIState, id: ServiceID, siteGuarded: Boolean?): String? {
    state.failure?.let { return it }
    if (state.sites == null) return null
    val site = state.site(id) ?: return stringResource(R.string.api_no_site)
    if (!site.editable) return stringResource(R.string.api_hand_edited)
    if (siteGuarded == false) return stringResource(R.string.api_guard_off)
    return null
}

/** One service's API switches in their own sheet */
@Composable
fun ServiceOpenAPISheet(
    deployment: Deployment,
    id: ServiceID,
    name: String,
    model: OpenAPIViewModel,
    siteGuarded: Boolean? = null,
    onClose: () -> Unit,
) {
    LaunchedEffect(deployment.id, id) { model.refresh(deployment) }
    IOSSheet(title = name, onClose = onClose, closeLabel = stringResource(R.string.containers_done)) {
        OpenAPIGroupsSection(deployment, id, model, siteGuarded)
    }
}

/** One switch for every service's app APIs */
@Composable
fun AllOpenAPISection(deployment: Deployment, services: List<ServiceID>, model: OpenAPIViewModel) {
    val state by model.state.collectAsState()
    val all = state.allOpen(services)
    GroupedSection(
        header = stringResource(R.string.api_all_header),
        note = stringResource(R.string.api_all_note),
        onRefresh = { model.refresh(deployment) },
        refreshDescription = stringResource(R.string.refresh_this_again),
        refreshing = state.loading || state.busy.isNotEmpty(),
        footer = state.failure,
    ) {
        GroupedRow(
            showDivider = false,
            leading = { Icon(Icons.Outlined.Apps, contentDescription = null, modifier = Modifier.size(22.dp), tint = Gryonix.colors.accent) },
            trailing = {
                IOSSwitch(
                    checked = all == true,
                    enabled = state.sites != null && state.busy.isEmpty(),
                    onCheckedChange = { model.setAll(deployment, it, services) },
                )
            },
        ) {
            RowLabel(
                stringResource(R.string.api_all_switch),
                if (all == null && state.sites != null) stringResource(R.string.api_all_mixed) else null,
            )
        }
    }
}

/** Whether this server offers the API switches */
fun offersOpenAPI(deployment: Deployment): Boolean =
    deployment.usesAgent && OpenAPIViewModel.services(deployment).isNotEmpty()
