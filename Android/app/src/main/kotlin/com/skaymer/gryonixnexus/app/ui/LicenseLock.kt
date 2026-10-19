package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import com.skaymer.gryonixnexus.app.licensing.LicensePrompt
import com.skaymer.gryonixnexus.app.licensing.LicenseStatus
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.ProminentButton
import com.skaymer.gryonixnexus.app.ui.design.ValueRow

/** "Unlock in the full version" or "Activate your subscription" */
internal fun licenseLockMessage(): Int =
    if (LicenseGate.everActive) R.string.license_renew else R.string.license_unlock

/** Covers a screen with the lock card while unlicensed */
@Composable
fun LicenseLocked(exceptDemo: Boolean = false, demoOn: Boolean = false, content: @Composable () -> Unit) {
    val status by LicenseGate.status.collectAsState()
    if (status is LicenseStatus.Active || (exceptDemo && demoOn)) {
        content()
        return
    }
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().blur(6.dp)) { content() }
        LockCard()
    }
}

@Composable
internal fun LockCard() {
    val tapped = remember { MutableInteractionSource() }
    Box(
        Modifier
            .fillMaxSize()
            .clickable(interactionSource = tapped, indication = null) { LicensePrompt.showing.value = true },
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier
                .widthIn(max = 320.dp)
                .background(Gryonix.colors.groupedBackground, RoundedCornerShape(20.dp))
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(Icons.Filled.Lock, contentDescription = null, modifier = Modifier.size(36.dp))
            Text(
                stringResource(licenseLockMessage()),
                style = MaterialTheme.typography.titleMedium,
                textAlign = TextAlign.Center,
            )
            ProminentButton(
                text = stringResource(if (LicenseGate.everActive) R.string.license_activate else R.string.license_buy),
                onClick = { LicensePrompt.showing.value = true },
            )
        }
    }
}

@Composable
fun OwnAddressRow(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String? = null,
    showDivider: Boolean = true,
) {
    val status by LicenseGate.status.collectAsState()
    if (status is LicenseStatus.Active) {
        FieldRow(label, value, onValueChange, placeholder = placeholder, showDivider = showDivider)
    } else {
        ValueRow(
            title = label,
            value = value.ifBlank { placeholder.orEmpty() },
            onClick = { LicensePrompt.showing.value = true },
            showDivider = showDivider,
        )
    }
}

/** The lock sheet, raised from anywhere in the app */
@Composable
fun LicensePromptHost(store: SettingsStore, fleet: FleetRepository) {
    val showing by LicensePrompt.showing.collectAsState()
    val status by LicenseGate.status.collectAsState()
    LaunchedEffect(status) {
        if (status is LicenseStatus.Active) LicensePrompt.showing.value = false
    }
    if (!showing) return
    IOSSheet(
        title = stringResource(R.string.license_title),
        onClose = { LicensePrompt.showing.value = false },
        closeLabel = stringResource(R.string.license_close),
    ) {
        LicenseSections(store, fleet, locked = true)
    }
}
