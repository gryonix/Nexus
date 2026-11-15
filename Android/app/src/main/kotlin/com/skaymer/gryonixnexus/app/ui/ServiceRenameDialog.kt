package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.catalog.ManagedService

/** The name a service shows on this server */
@Composable
fun ServiceNameRow(service: ManagedService, current: String, onRename: (String) -> Unit) {
    PendingTextRow(
        label = stringResource(R.string.name_label),
        saved = current,
        placeholder = service.displayName,
        valid = { true },
        onApply = { name -> onRename(if (name.trim() == service.displayName) "" else name.trim()) },
    )
}

/** Gives each service its name on this server */
@Composable
fun serviceTitles(deploymentID: String): (ManagedService) -> String {
    val names = (LocalContext.current.applicationContext as? GryonixApplication)?.serviceNames
        ?: return { it.displayName }
    val servers by names.servers.collectAsState()
    val given = servers[deploymentID].orEmpty()
    return { given[it.id.rawValue] ?: it.displayName }
}
