package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.install.InstallTarget
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.catalog.storage.SwapPlan

/** Adds a swap file right after the connection check */
@Composable
fun SwapRow(target: InstallTarget, onAdd: (Int) -> Unit) {
    if (target.connection !is InstallTarget.Connection.Ok || target.hardware == null) return
    var asking by remember { mutableStateOf(false) }
    var custom by remember { mutableStateOf(false) }
    val adding = target.swap is InstallTarget.Swap.Adding
    val current = currentSwap(target.hardware.swapBytes)
    ValueRow(stringResource(R.string.swap_now), current, null)
    ActionRow(
        text = stringResource(if (adding) R.string.swap_adding else R.string.swap_add),
        onClick = { asking = true },
        enabled = !adding,
        showDivider = target.swap is InstallTarget.Swap.Failed,
    )
    (target.swap as? InstallTarget.Swap.Failed)?.let { failed ->
        VerdictRow(failed.reason, Gryonix.colors.danger)
    }
    if (asking) {
        IOSAlert(
            title = stringResource(R.string.swap_title),
            message = stringResource(R.string.swap_now_note, current),
            onDismiss = { asking = false },
            actions = SwapPlan.SIZES.map { size ->
                AlertAction(stringResource(R.string.swap_size, size.toString())) { asking = false; onAdd(size) }
            } + AlertAction(stringResource(R.string.swap_other)) { asking = false; custom = true } +
                AlertAction(stringResource(R.string.close)) { asking = false },
        )
    }
    if (custom) CustomSwapSizeAlert(onSet = onAdd, onDismiss = { custom = false })
}

/** Swap size in words, or None */
@Composable
internal fun currentSwap(size: Long): String =
    if (size > 0) bytes(size) else stringResource(R.string.storage_none)
