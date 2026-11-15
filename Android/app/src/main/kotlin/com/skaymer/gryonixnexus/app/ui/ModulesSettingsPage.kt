package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.shell.AppModule
import com.skaymer.gryonixnexus.app.shell.ModuleSettings
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.servercontrol.Deployment

internal val AppModule.titleRes: Int
    get() = when (this) {
        AppModule.AI -> R.string.module_ai
        AppModule.VPN_ADVANCED -> R.string.module_vpn_advanced
        AppModule.PORT_FORWARDING -> R.string.module_port_forwarding
        AppModule.SCRIPTS -> R.string.module_scripts
        AppModule.DOCKER_ADVANCED -> R.string.module_docker_advanced
    }

internal val AppModule.noteRes: Int
    get() = when (this) {
        AppModule.AI -> R.string.module_ai_note
        AppModule.VPN_ADVANCED -> R.string.module_vpn_advanced_note
        AppModule.PORT_FORWARDING -> R.string.module_port_forwarding_note
        AppModule.SCRIPTS -> R.string.module_scripts_note
        AppModule.DOCKER_ADVANCED -> R.string.module_docker_advanced_note
    }

/** Settings, Modules: what the app shows, here or per server */
@Composable
fun ModulesSettingsPage(modules: ModuleSettings) {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val kept by modules.keptOnServers.collectAsState()
    val servers by app.fleet.deployments.collectAsState()
    var pendingAgreement by remember { mutableStateOf<(() -> Unit)?>(null) }
    var opened by remember { mutableStateOf<Deployment?>(null) }
    val ask: (AppModule, Boolean, () -> Unit) -> Unit = { module, on, apply ->
        if (module == AppModule.AI && on && !app.aiSettings.config.value.agreed) pendingAgreement = apply else apply()
    }
    pendingAgreement?.let { apply ->
        AiAgreement(
            onAgree = { app.aiSettings.update { it.copy(agreed = true) }; apply(); pendingAgreement = null },
            onCancel = { pendingAgreement = null },
        )
        return
    }
    opened?.let { server -> ServerModulesSheet(server, modules, ask) { opened = null } }
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item {
            GroupedSection(
                header = stringResource(R.string.modules_where),
                note = stringResource(R.string.modules_where_note) + "\n\n" + stringResource(R.string.modules_footer),
            ) {
                ToggleRow(stringResource(R.string.modules_on_servers), kept, { modules.setKeptOnServers(it) }, showDivider = false)
            }
        }
        item {
            if (kept) {
                GroupedSection {
                    servers.forEachIndexed { index, server ->
                        ValueRow(server.name, null, { opened = server }, showDivider = index != servers.lastIndex)
                    }
                }
            } else {
                GroupedSection(header = stringResource(R.string.modules_on_device)) {
                    LocalModuleRows(modules, ask)
                }
            }
        }
    }
}

@Composable
private fun ColumnScope.LocalModuleRows(modules: ModuleSettings, ask: (AppModule, Boolean, () -> Unit) -> Unit) {
    val on by modules.on.collectAsState()
    AppModule.entries.forEach { module ->
        ToggleRow(
            title = stringResource(module.titleRes),
            checked = module in on,
            onCheckedChange = { value -> ask(module, value) { modules.set(module, value) } },
            showDivider = module != AppModule.entries.last(),
            infoNote = stringResource(module.noteRes),
        )
    }
}
