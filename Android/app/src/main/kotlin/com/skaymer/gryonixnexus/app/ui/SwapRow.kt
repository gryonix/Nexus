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
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.app.ui.design.WheelRow
import com.skaymer.gryonixnexus.catalog.storage.SwapPlan

/** Adds a swap file right after the connection check */
@Composable
fun SwapRow(target: InstallTarget, onAdd: (Int) -> Unit) {
    if (target.connection !is InstallTarget.Connection.Ok || target.hardware == null) return
    var size by remember { mutableStateOf(2) }
    val adding = target.swap is InstallTarget.Swap.Adding
    ValueRow(stringResource(R.string.swap_now), currentSwap(target.hardware.swapBytes), null)
    val sizes = SwapPlan.WHEEL.drop(1)
    if (!adding) {
        WheelRow(
            title = stringResource(R.string.swap_title),
            choices = sizes.map { stringResource(R.string.swap_size, it.toString()) },
            selected = sizes.indexOf(size),
            onSelect = { size = sizes[it] },
        )
    }
    ActionRow(
        text = stringResource(if (adding) R.string.swap_adding else R.string.swap_add),
        onClick = { onAdd(size) },
        enabled = !adding,
        showDivider = target.swap is InstallTarget.Swap.Failed,
    )
    (target.swap as? InstallTarget.Swap.Failed)?.let { failed ->
        VerdictRow(failed.reason, Gryonix.colors.danger)
    }
}

/** Swap size in words, or None */
@Composable
internal fun currentSwap(size: Long): String =
    if (size > 0) bytes(size) else stringResource(R.string.storage_none)
