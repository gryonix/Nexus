package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.servercontrol.DiskChoice

/** Average, every disk, or one disk for the disk chart */
@Composable
internal fun DiskChoiceButton(mounts: List<String>, choice: DiskChoice, onChoose: (DiskChoice) -> Unit) {
    val average = stringResource(R.string.history_disks_average)
    val each = stringResource(R.string.history_disks_each)
    val current = when (choice) {
        DiskChoice.Average -> average
        DiskChoice.Each -> each
        is DiskChoice.One -> choice.mount
    }
    ChoiceRow(
        title = stringResource(R.string.history_disks),
        value = current,
        showDivider = false,
        options = listOf(average to { onChoose(DiskChoice.Average) }, each to { onChoose(DiskChoice.Each) }) +
            mounts.map { mount -> mount to { onChoose(DiskChoice.One(mount)) } },
    )
}
