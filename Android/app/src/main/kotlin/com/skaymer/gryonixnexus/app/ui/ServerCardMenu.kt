package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.ServerTint
import com.skaymer.gryonixnexus.servercontrol.MetricsIndicatorStyle
import com.skaymer.gryonixnexus.servercontrol.ServerCardSize

/** Which list the open menu is showing */
private enum class CardMenuPage { ROOT, SIZE, INDICATOR, COLOR }

@Composable
fun ServerCardMenu(
    expanded: Boolean,
    name: String,
    size: ServerCardSize?,
    style: MetricsIndicatorStyle?,
    tint: String?,
    onDismiss: () -> Unit,
    onSize: (ServerCardSize?) -> Unit,
    onIndicator: (MetricsIndicatorStyle?) -> Unit,
    onTint: (String?) -> Unit,
    onForget: () -> Unit,
    onExport: () -> Unit,
    /** Addresses, passwords and pinned host keys — see `ConnectionEdit` */
    onConnection: () -> Unit,
    onAccess: () -> Unit,
) {
    var page by remember { mutableStateOf(CardMenuPage.ROOT) }
    LaunchedEffect(expanded) { if (!expanded) page = CardMenuPage.ROOT }

    var confirming by remember { mutableStateOf(false) }

    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        when (page) {
            CardMenuPage.ROOT -> {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.card_size)) },
                    onClick = { page = CardMenuPage.SIZE }
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.card_indicator)) },
                    onClick = { page = CardMenuPage.INDICATOR }
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.card_color)) },
                    onClick = { page = CardMenuPage.COLOR }
                )
                HorizontalDivider()
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.server_settings)) },
                    onClick = { onDismiss(); onConnection() }
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.server_access_title)) },
                    onClick = { onDismiss(); onAccess() }
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.card_export)) },
                    onClick = { onDismiss(); onExport() }
                )
                HorizontalDivider()
                DropdownMenuItem(
                    text = {
                        Text(
                            stringResource(R.string.card_delete),
                            color = MaterialTheme.colorScheme.error
                        )
                    },
                    onClick = { onDismiss(); confirming = true }
                )
            }
            CardMenuPage.SIZE -> {
                BackItem(stringResource(R.string.card_size)) { page = CardMenuPage.ROOT }
                Choice(stringResource(R.string.card_default), size == null) {
                    onSize(null); onDismiss()
                }
                Choice(stringResource(R.string.card_wide), size == ServerCardSize.WIDE) {
                    onSize(ServerCardSize.WIDE); onDismiss()
                }
                Choice(stringResource(R.string.card_compact), size == ServerCardSize.COMPACT) {
                    onSize(ServerCardSize.COMPACT); onDismiss()
                }
            }
            CardMenuPage.INDICATOR -> {
                BackItem(stringResource(R.string.card_indicator)) { page = CardMenuPage.ROOT }
                Choice(stringResource(R.string.card_default), style == null) {
                    onIndicator(null); onDismiss()
                }
                MetricsIndicatorStyle.entries.forEach { option ->
                    Choice(stringResource(option.labelRes), style == option) {
                        onIndicator(option); onDismiss()
                    }
                }
            }
            CardMenuPage.COLOR -> {
                BackItem(stringResource(R.string.card_color)) { page = CardMenuPage.ROOT }
                Choice(stringResource(R.string.tint_default), tint == null) {
                    onTint(null); onDismiss()
                }
                ServerTint.entries.forEach { option ->
                    Choice(
                        label = stringResource(option.labelRes),
                        chosen = ServerTint.of(tint) == option,
                        swatch = option,
                    ) { onTint(option.raw); onDismiss() }
                }
            }
        }
    }

    if (confirming) {
        ConfirmAlert(
            title = stringResource(R.string.delete_server_title, name),
            message = stringResource(R.string.delete_server_message),
            confirm = stringResource(R.string.delete_server_confirm),
            cancel = stringResource(R.string.delete_server_cancel),
            destructive = true,
            onConfirm = { confirming = false; onForget() },
            onCancel = { confirming = false },
        )
    }
}

@Composable
private fun BackItem(title: String, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(title, style = MaterialTheme.typography.titleSmall) },
        leadingIcon = {
            Icon(
                Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = stringResource(R.string.card_menu_back)
            )
        },
        onClick = onClick
    )
}

@Composable
private fun Choice(
    label: String,
    chosen: Boolean,
    swatch: ServerTint? = null,
    onClick: () -> Unit,
) {
    DropdownMenuItem(
        text = { Text(label) },
        leadingIcon = {
            if (swatch != null) {
                Box(Modifier.size(16.dp).background(swatch.composeColor(), CircleShape))
            } else {
                Box(Modifier.size(24.dp))
            }
        },
        trailingIcon = { if (chosen) Icon(Icons.Filled.Check, contentDescription = null) },
        onClick = onClick
    )
}
