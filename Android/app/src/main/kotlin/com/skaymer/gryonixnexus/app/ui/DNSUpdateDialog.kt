package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert

/** Asks before DNS records change, then says how it went */
@Composable
fun DNSUpdateDialog() {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val update by app.dnsUpdate.collectAsState()
    val result by app.dnsUpdateResult.collectAsState()
    update?.let { pending ->
        val lines = listOfNotNull(
            pending.add.takeIf { it.isNotEmpty() }?.let { stringResource(R.string.dns_update_add, it.joinToString(", ")) },
            pending.remove.takeIf { it.isNotEmpty() }?.let { stringResource(R.string.dns_update_remove, it.joinToString(", ")) },
        )
        IOSAlert(
            title = stringResource(R.string.dns_update_title),
            message = lines.joinToString("\n"),
            onDismiss = { app.dnsUpdate.value = null },
            actions = listOf(
                AlertAction(stringResource(R.string.agent_update_later), onSelect = { app.dnsUpdate.value = null }),
                AlertAction(stringResource(R.string.containers_update), preferred = true, onSelect = { app.applyDNSUpdate(pending) }),
            ),
        )
    }
    result?.takeIf { it.isNotEmpty() && update == null }?.let { lines ->
        IOSAlert(
            title = stringResource(R.string.dns_update_title),
            message = lines.joinToString("\n"),
            onDismiss = { app.dnsUpdateResult.value = null },
            actions = listOf(AlertAction(stringResource(R.string.close), preferred = true, onSelect = { app.dnsUpdateResult.value = null })),
        )
    }
}
