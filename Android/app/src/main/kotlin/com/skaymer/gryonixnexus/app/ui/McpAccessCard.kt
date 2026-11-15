package com.skaymer.gryonixnexus.app.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.shell.AppModule
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.McpClientConfig
import com.skaymer.gryonixnexus.servercontrol.SshKeyKind
import com.skaymer.gryonixnexus.servercontrol.UserSshKey
import com.skaymer.gryonixnexus.transport.UserSshKeyGenerator
import gryonixnexusd.v1.McpAccessState
import kotlinx.coroutines.launch

/** The read-only MCP door for outside AI agents */
@Composable
fun McpAccessCard(deployment: Deployment) {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val on by app.modules.on.collectAsState()
    if (AppModule.AI !in on) return
    var state by remember(deployment.id) { mutableStateOf<McpAccessState?>(null) }
    var key by remember(deployment.id) { mutableStateOf<UserSshKey?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(deployment.id) { state = runCatching { app.mcpAccess(deployment, null) }.getOrNull() }
    GroupedSection(header = stringResource(R.string.mcp_header), note = stringResource(R.string.mcp_note)) {
        ToggleRow(
            title = stringResource(R.string.mcp_toggle),
            subtitle = error,
            checked = state?.enabled == true,
            enabled = state != null && !busy,
            onCheckedChange = { wanted ->
                busy = true
                scope.launch {
                    runCatching {
                        if (wanted) {
                            val fresh = UserSshKeyGenerator.generate(SshKeyKind.ED25519, "gryonix-mcp")
                            state = app.mcpAccess(deployment, true, fresh.publicKey)
                            key = fresh
                        } else {
                            state = app.mcpAccess(deployment, false)
                            key = null
                        }
                    }.onSuccess { error = null }.onFailure { error = it.message ?: it.toString() }
                    busy = false
                }
            },
            showDivider = key != null,
        )
        key?.let { McpKeyHandout(it, config(deployment, state)) }
    }
}

private fun config(deployment: Deployment, state: McpAccessState?): String =
    McpClientConfig.text(deployment.name, state?.users?.firstOrNull() ?: "admin", deployment.entry.host, "~/.ssh/gryonix-mcp")

@Composable
private fun McpKeyHandout(key: UserSshKey, config: String) {
    val context = LocalContext.current
    Text(stringResource(R.string.mcp_handout), style = MaterialTheme.typography.bodySmall,
        color = Gryonix.colors.secondaryLabel, modifier = Modifier.padding(Metrics.listInset))
    ActionRow(stringResource(R.string.mcp_copy_key), onClick = { copy(context, key.privateKeyPem) })
    ActionRow(stringResource(R.string.mcp_copy_config), onClick = { copy(context, config) })
    Text(config, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall,
        modifier = Modifier.padding(Metrics.listInset))
}

private fun copy(context: Context, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText("gryonix", text))
}
