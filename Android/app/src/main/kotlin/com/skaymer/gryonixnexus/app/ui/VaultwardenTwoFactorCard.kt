package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.agentcontrol.VaultwardenTwoFactorStatus
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** Warns when a Vaultwarden account has no two-factor login */
@Composable
fun VaultwardenTwoFactorCard(deployment: Deployment, showDivider: Boolean = true) {
    val model = (LocalContext.current.applicationContext as GryonixApplication).vaultwardenTwoFactor
    val answers by model.state.collectAsState()
    LaunchedEffect(deployment.id) { model.load(deployment) }
    val status = answers[deployment.id]
    ValueRow(
        title = stringResource(R.string.vaultwarden_two_factor),
        value = status?.let { summary(it) },
        onClick = null,
        subtitle = if (status?.needsAttention == true) stringResource(R.string.vaultwarden_two_factor_note) else null,
        showDivider = showDivider,
        leading = status?.let { { TwoFactorIcon(it) } },
    )
}

@Composable
private fun summary(status: VaultwardenTwoFactorStatus): String =
    if (status.needsAttention) {
        stringResource(R.string.vaultwarden_two_factor_missing, status.usersWithoutTwoFactor, status.users)
    } else {
        stringResource(R.string.vaultwarden_two_factor_everyone)
    }

@Composable
private fun TwoFactorIcon(status: VaultwardenTwoFactorStatus) {
    Icon(
        if (status.needsAttention) Icons.Filled.Warning else Icons.Filled.CheckCircle,
        contentDescription = null,
        tint = if (status.needsAttention) Gryonix.colors.warning else Gryonix.colors.success,
        modifier = Modifier.size(22.dp),
    )
}
