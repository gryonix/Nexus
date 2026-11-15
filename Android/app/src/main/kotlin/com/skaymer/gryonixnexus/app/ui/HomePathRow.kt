package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.servercontrol.HomePathChoice

private fun HomePathChoice.labelRes(): Int = when (this) {
    HomePathChoice.AUTOMATIC -> R.string.home_path_automatic
    HomePathChoice.THROUGH_VPS -> R.string.home_path_vps
    HomePathChoice.LOCAL_NETWORK -> R.string.home_path_local
}

/** Picks how this device reaches the local machine */
@Composable
fun HomePathRow(choice: HomePathChoice, showDivider: Boolean = true, onChange: (HomePathChoice) -> Unit) {
    ChoiceRow(
        title = stringResource(R.string.home_path_title),
        value = stringResource(choice.labelRes()),
        showDivider = showDivider,
        options = HomePathChoice.entries.map { stringResource(it.labelRes()) to { onChange(it) } },
    )
}
