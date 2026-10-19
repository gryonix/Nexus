package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.runtime.staticCompositionLocalOf
import com.skaymer.gryonixnexus.app.shell.Haptics

/** How a press answers, from anywhere in the design system */
val LocalHaptics = staticCompositionLocalOf<(Haptics.Feel) -> Unit> { {} }
