package com.skaymer.gryonixnexus.app.ui

import androidx.annotation.StringRes
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.ServerTint
import com.skaymer.gryonixnexus.servercontrol.MetricsIndicatorStyle

/** The words and colours the appearance choices are shown with */
@get:StringRes
val MetricsIndicatorStyle.labelRes: Int
    get() = when (this) {
        MetricsIndicatorStyle.BARS -> R.string.indicator_bars
        MetricsIndicatorStyle.TRACK -> R.string.indicator_line
        MetricsIndicatorStyle.RINGS -> R.string.indicator_rings
        MetricsIndicatorStyle.MINIMAL -> R.string.indicator_minimal
    }

@get:StringRes
val ServerTint.labelRes: Int
    get() = when (this) {
        ServerTint.BLUE -> R.string.tint_blue
        ServerTint.TEAL -> R.string.tint_teal
        ServerTint.GREEN -> R.string.tint_green
        ServerTint.ORANGE -> R.string.tint_orange
        ServerTint.PINK -> R.string.tint_pink
        ServerTint.PURPLE -> R.string.tint_purple
        ServerTint.RED -> R.string.tint_red
        ServerTint.GRAY -> R.string.tint_gray
    }

@Composable
fun ServerTint?.composeColor(): Color = when (this) {
    ServerTint.BLUE -> Color(0xFF0A84FF)
    ServerTint.TEAL -> Color(0xFF30B0C7)
    ServerTint.GREEN -> Color(0xFF34C759)
    ServerTint.ORANGE -> Color(0xFFFF9500)
    ServerTint.PINK -> Color(0xFFFF2D55)
    ServerTint.PURPLE -> Color(0xFFAF52DE)
    ServerTint.RED -> Color(0xFFFF3B30)
    ServerTint.GRAY -> Color(0xFF8E8E93)
    null -> MaterialTheme.colorScheme.primary
}
