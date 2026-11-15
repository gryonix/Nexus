package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.shell.AppModule
import com.skaymer.gryonixnexus.app.shell.ModuleSettings
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.launch

/** One server's modules, read from and written to its agent */
@Composable
fun ServerModulesSheet(
    server: Deployment,
    modules: ModuleSettings,
    ask: (AppModule, Boolean, () -> Unit) -> Unit,
    onClose: () -> Unit,
) {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val sets by modules.servers.collectAsState()
    val scope = rememberCoroutineScope()
    var loading by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    val oldAgent = stringResource(R.string.modules_old_agent)
    LaunchedEffect(server.id) {
        if (!app.loadAppModules(server)) failure = oldAgent
        loading = false
    }
    IOSSheet(title = server.name, onClose = onClose, closeLabel = stringResource(R.string.close)) {
        GroupedSection(footer = failure) {
            AppModule.entries.forEach { module ->
                ToggleRow(
                    title = stringResource(module.titleRes),
                    checked = sets[server.id]?.contains(module.id) == true,
                    onCheckedChange = { value ->
                        ask(module, value) {
                            val next = modules.set(module, value, server.id)
                            scope.launch {
                                failure = runCatching { app.saveAppModules(server, next) }.exceptionOrNull()?.message
                            }
                        }
                    },
                    enabled = !loading,
                    showDivider = module != AppModule.entries.last(),
                    infoNote = stringResource(module.noteRes),
                )
            }
        }
    }
}
