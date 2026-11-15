package com.skaymer.gryonixnexus.app.ui.design

import android.graphics.Color
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect

/** Keeps the status and navigation bars readable in both themes */
@Composable
fun SystemBarsFollowTheme(activity: ComponentActivity) {
    val dark = isSystemInDarkTheme()
    LaunchedEffect(dark) {
        activity.enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(Color.TRANSPARENT, Color.TRANSPARENT) { dark },
            navigationBarStyle = SystemBarStyle.auto(LIGHT_SCRIM, DARK_SCRIM) { dark },
        )
    }
}

private val LIGHT_SCRIM = Color.argb(0xE6, 0xFF, 0xFF, 0xFF)
private val DARK_SCRIM = Color.argb(0x80, 0x1B, 0x1B, 0x1B)
