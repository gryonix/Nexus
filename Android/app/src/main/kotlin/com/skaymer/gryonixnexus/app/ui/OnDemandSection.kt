package com.skaymer.gryonixnexus.app.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.core.content.ContextCompat
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.vpn.OnDemandPolicy
import com.skaymer.gryonixnexus.app.vpn.OnDemandSettings

/** When this device's tunnel comes up on its own */
@Composable
fun OnDemandSection(settings: OnDemandSettings) {
    val policy by settings.policy.collectAsState()
    val listsNetworks = policy.isEnabled && policy.scope != OnDemandPolicy.Scope.CELLULAR
    GroupedSection(
        header = stringResource(R.string.vpn_on_demand_title),
        note = stringResource(
            when {
                !listsNetworks -> R.string.vpn_on_demand_hint
                policy.mode == OnDemandPolicy.NetworkMode.ONLY_LISTED -> R.string.vpn_on_demand_only_hint
                else -> R.string.vpn_on_demand_except_hint
            },
        ),
    ) {
        ToggleRow(
            title = stringResource(R.string.vpn_on_demand_toggle),
            checked = policy.isEnabled,
            onCheckedChange = { on -> settings.update { it.copy(isEnabled = on) } },
            showDivider = policy.isEnabled,
        )
        if (policy.isEnabled) ScopeRow(policy.scope) { scope -> settings.update { it.copy(scope = scope) } }
        if (listsNetworks) NetworkRows(settings, policy)
    }
}

@Composable
private fun ScopeRow(scope: OnDemandPolicy.Scope, onSelect: (OnDemandPolicy.Scope) -> Unit) {
    GroupedRow {
        IOSSegmentedControl(
            segments = OnDemandPolicy.Scope.entries,
            selected = scope,
            modifier = Modifier.weight(1f),
            label = {
                stringResource(
                    when (it) {
                        OnDemandPolicy.Scope.ANY -> R.string.vpn_on_demand_any
                        OnDemandPolicy.Scope.WIFI -> R.string.vpn_on_demand_wifi
                        OnDemandPolicy.Scope.CELLULAR -> R.string.vpn_on_demand_cellular
                    },
                )
            },
            onSelect = onSelect,
        )
    }
}

@Composable
private fun NetworkRows(settings: OnDemandSettings, policy: OnDemandPolicy) {
    val context = LocalContext.current
    val askLocation = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
    var draft by rememberSaveable { mutableStateOf("") }
    GroupedRow {
        IOSSegmentedControl(
            segments = OnDemandPolicy.NetworkMode.entries,
            selected = policy.mode,
            modifier = Modifier.weight(1f),
            label = {
                stringResource(
                    if (it == OnDemandPolicy.NetworkMode.ONLY_LISTED) R.string.vpn_on_demand_only_listed
                    else R.string.vpn_on_demand_except_listed,
                )
            },
            onSelect = { mode -> settings.update { it.copy(mode = mode) } },
        )
    }
    policy.networks.forEach { network ->
        GroupedRow(
            trailing = {
                IconButton(onClick = { settings.removeNetwork(network) }) {
                    Icon(Icons.Filled.Delete, contentDescription = stringResource(R.string.vpn_on_demand_remove))
                }
            },
        ) { RowLabel(network) }
    }
    FieldRow(
        label = stringResource(R.string.vpn_on_demand_network),
        value = draft,
        onValueChange = { draft = it },
    )
    ActionRow(
        text = stringResource(R.string.vpn_on_demand_add),
        enabled = draft.isNotBlank(),
        showDivider = false,
        onClick = {
            settings.addNetwork(draft)
            draft = ""
            val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
            if (!granted) askLocation.launch(Manifest.permission.ACCESS_FINE_LOCATION)
        },
    )
}
