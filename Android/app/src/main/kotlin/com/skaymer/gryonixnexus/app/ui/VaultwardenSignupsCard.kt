package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.catalog.ServiceID

/** Opens or closes Vaultwarden's new-account sign-up */
@Composable
fun VaultwardenSignupsCard(
    deployment: Deployment,
    onChange: (Boolean) -> Unit,
    showDivider: Boolean = true,
) {
    var confirmingOpen by rememberSaveable(deployment.id) { mutableStateOf(false) }
    ToggleRow(
        title = stringResource(R.string.vaultwarden_signups),
        checked = deployment.serviceSettings.vaultwardenAllowSignups,
        onCheckedChange = { open -> if (open) confirmingOpen = true else onChange(false) },
        showDivider = showDivider,
        infoNote = stringResource(R.string.vaultwarden_signups_note),
    )
    if (confirmingOpen) {
        ConfirmAlert(
            title = stringResource(R.string.vaultwarden_signups_open_title),
            message = stringResource(R.string.vaultwarden_signups_open_message),
            confirm = stringResource(R.string.vaultwarden_signups_open),
            onConfirm = {
                confirmingOpen = false
                onChange(true)
            },
            onCancel = { confirmingOpen = false },
        )
    }
}

/** Vaultwarden runs here and the agent can re-apply it */
fun canToggleVaultwardenSignups(deployment: Deployment): Boolean =
    deployment.usesAgent && ServiceID.VAULTWARDEN in deployment.services
