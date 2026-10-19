package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.MetricsIndicatorStyle

object MetricsDisplaySettings {
    const val INDICATOR_STYLE_KEY = "metrics.indicatorStyle"

    fun raw(style: MetricsIndicatorStyle): String = when (style) {
        MetricsIndicatorStyle.BARS -> "bars"
        MetricsIndicatorStyle.TRACK -> "track"
        MetricsIndicatorStyle.RINGS -> "rings"
        MetricsIndicatorStyle.MINIMAL -> "minimal"
    }

    fun indicatorStyle(stored: String?): MetricsIndicatorStyle =
        MetricsIndicatorStyle.entries.firstOrNull { raw(it) == stored }
            ?: MetricsIndicatorStyle.BARS
}
