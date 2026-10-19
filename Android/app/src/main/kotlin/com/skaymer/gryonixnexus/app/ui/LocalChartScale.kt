package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.staticCompositionLocalOf
import com.skaymer.gryonixnexus.app.metrics.OfferedCharts

/** Whether charts fit their axis to the data */
val LocalChartAutoScale = staticCompositionLocalOf { true }

/** Which periods and metrics the charts offer */
val LocalOfferedCharts = staticCompositionLocalOf { OfferedCharts.everything }
