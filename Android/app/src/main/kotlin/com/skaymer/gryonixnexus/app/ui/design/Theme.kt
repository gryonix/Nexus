package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.shape.RoundedCornerShape
import com.skaymer.gryonixnexus.app.shell.AppAccent

@Composable
fun GryonixTheme(
    dark: Boolean = isSystemInDarkTheme(),
    /** The chosen accent */
    accent: AppAccent = AppAccent.APP,
    content: @Composable () -> Unit,
) {
    val colors = (if (dark) DarkColors else LightColors).withAccent(accent)
    val scheme = remember(colors) { colors.materialScheme() }
    CompositionLocalProvider(LocalGryonixColors provides colors) {
        MaterialTheme(
            colorScheme = scheme,
            typography = GryonixTypography,
            shapes = GryonixShapes,
            content = content,
        )
    }
}

/** The palette, from anywhere: `Gryonix.colors.accent` */
object Gryonix {
    val colors: GryonixColors
        @Composable @ReadOnlyComposable get() = LocalGryonixColors.current
}

/** The iOS palette expressed as a Material scheme */
private fun GryonixColors.materialScheme() = if (isDark) {
    darkColorScheme(
        primary = accent,
        onPrimary = Color.White,
        primaryContainer = accent,
        onPrimaryContainer = Color.White,
        secondary = accent,
        onSecondary = Color.White,
        background = groupedBackground,
        onBackground = label,
        surface = cardBackground,
        onSurface = label,
        surfaceVariant = cardBackground,
        onSurfaceVariant = secondaryLabel,
        surfaceContainer = cardBackground,
        surfaceContainerHigh = cardBackground,
        surfaceContainerHighest = cardBackground,
        surfaceContainerLow = groupedBackground,
        surfaceContainerLowest = groupedBackground,
        outline = separator,
        outlineVariant = separator,
        error = danger,
        onError = Color.White,
        errorContainer = danger,
        onErrorContainer = Color.White,
        scrim = Color.Black.copy(alpha = 0.4f),
    )
} else {
    lightColorScheme(
        primary = accent,
        onPrimary = Color.White,
        primaryContainer = accent,
        onPrimaryContainer = Color.White,
        secondary = accent,
        onSecondary = Color.White,
        background = groupedBackground,
        onBackground = label,
        surface = cardBackground,
        onSurface = label,
        surfaceVariant = cardBackground,
        onSurfaceVariant = secondaryLabel,
        surfaceContainer = cardBackground,
        surfaceContainerHigh = cardBackground,
        surfaceContainerHighest = cardBackground,
        surfaceContainerLow = groupedBackground,
        surfaceContainerLowest = groupedBackground,
        outline = separator,
        outlineVariant = separator,
        error = danger,
        onError = Color.White,
        errorContainer = danger,
        onErrorContainer = Color.White,
        scrim = Color.Black.copy(alpha = 0.4f),
    )
}

/** The corner radii the iPhone app is cut with */
val GryonixShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(10.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(16.dp),
    extraLarge = RoundedCornerShape(20.dp),
)

private val TightLineHeight = LineHeightStyle(
    alignment = LineHeightStyle.Alignment.Center,
    trim = LineHeightStyle.Trim.None,
)

private fun sf(
    size: Int,
    lineHeight: Int,
    weight: FontWeight = FontWeight.Normal,
    tracking: Double = 0.0,
) = TextStyle(
    fontSize = size.sp,
    lineHeight = lineHeight.sp,
    fontWeight = weight,
    letterSpacing = tracking.sp,
    lineHeightStyle = TightLineHeight,
)

val GryonixTypography = Typography(
    displayLarge = sf(34, 41, FontWeight.Bold, -0.4),
    displayMedium = sf(28, 34, FontWeight.Bold, -0.3),
    displaySmall = sf(22, 28, FontWeight.Bold, -0.2),
    headlineLarge = sf(34, 41, FontWeight.Bold, -0.4),
    headlineMedium = sf(28, 34, FontWeight.SemiBold, -0.3),
    headlineSmall = sf(20, 25, FontWeight.SemiBold, -0.2),
    titleLarge = sf(17, 22, FontWeight.SemiBold, -0.4),
    titleMedium = sf(17, 22, FontWeight.SemiBold, -0.4),
    titleSmall = sf(15, 20, FontWeight.SemiBold, -0.2),
    // Body 17, subheadline 15, footnote 13.
    bodyLarge = sf(17, 22, tracking = -0.4),
    bodyMedium = sf(15, 20, tracking = -0.2),
    bodySmall = sf(13, 18, tracking = -0.1),
    // What a control is labelled with, then caption1 and caption2.
    labelLarge = sf(17, 22, tracking = -0.4),
    labelMedium = sf(12, 16),
    labelSmall = sf(11, 13),
)
