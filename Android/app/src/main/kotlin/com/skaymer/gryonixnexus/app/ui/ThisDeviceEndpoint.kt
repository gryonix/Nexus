package com.skaymer.gryonixnexus.app.ui

import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.MenuCheckItem
import com.skaymer.gryonixnexus.app.ui.design.MenuHeader
import com.skaymer.gryonixnexus.app.ui.design.MenuValueRow
import com.skaymer.gryonixnexus.app.vpn.EndpointPin
import com.skaymer.gryonixnexus.app.vpn.EndpointPinStore
import com.skaymer.gryonixnexus.app.vpn.EndpointPins
import com.skaymer.gryonixnexus.app.vpn.LastTunnel
import com.skaymer.gryonixnexus.app.vpn.PinOutcome
import kotlinx.coroutines.launch

/** Stores a pin, or drops it when null */
typealias PinChange = (LastTunnel.Profile, EndpointPin?) -> Unit

/** The two ways to reach the server */
private class EndpointChoice(val byDomain: () -> Unit, val byAddress: () -> Unit)

/** The endpoint, its copy, and the domain or address choice */
@Composable
fun EndpointRow(
    profile: LastTunnel.Profile,
    endpoint: String,
    pinned: String?,
    enabled: Boolean,
    onPin: PinChange?,
) {
    val scope = rememberCoroutineScope()
    var looking by remember { mutableStateOf(false) }
    var refusal by remember { mutableStateOf<PinOutcome?>(null) }
    val choice = onPin?.takeIf { EndpointPins.offersChoice(profile.protocol, endpoint) }?.let { change ->
        EndpointChoice(
            byDomain = { change(profile, null) },
            byAddress = {
                scope.launch {
                    looking = true
                    when (val outcome = EndpointPinStore.lookUp(EndpointPins.hostOf(endpoint))) {
                        is PinOutcome.Pinned -> change(profile, outcome.pin)
                        else -> refusal = outcome
                    }
                    looking = false
                }
            },
        )
    }
    EndpointMenuRow(pinned ?: endpoint, pinned != null, enabled && !looking, choice)
    refusal?.let { PinRefusal(it) { refusal = null } }
}

@Composable
private fun EndpointMenuRow(shown: String, isPinned: Boolean, enabled: Boolean, choice: EndpointChoice?) {
    val clipboard = LocalClipboardManager.current
    MenuValueRow(stringResource(R.string.vpn_endpoint), shown, enabled, showDivider = false) { close ->
        MenuHeader(shown)
        DropdownMenuItem(
            text = { Text(stringResource(R.string.vpn_config_copy)) },
            onClick = { clipboard.setText(AnnotatedString(shown)); close() },
        )
        if (choice != null) {
            MenuHeader(stringResource(R.string.vpn_connect_by))
            MenuCheckItem(stringResource(R.string.vpn_connect_by_domain), !isPinned) {
                close()
                if (isPinned) choice.byDomain()
            }
            MenuCheckItem(stringResource(R.string.vpn_connect_by_address), isPinned) {
                close()
                if (!isPinned) choice.byAddress()
            }
        }
    }
}

/** Why the address cannot be pinned */
@Composable
private fun PinRefusal(outcome: PinOutcome, onClose: () -> Unit) {
    val message = when (outcome) {
        is PinOutcome.Private -> stringResource(R.string.vpn_pin_private, outcome.address)
        else -> stringResource(R.string.vpn_pin_not_found)
    }
    IOSAlert(
        title = stringResource(R.string.vpn_connect_by_address),
        onDismiss = onClose,
        message = message,
        actions = listOf(AlertAction(stringResource(R.string.actions_ok), preferred = true, onSelect = onClose)),
    )
}
