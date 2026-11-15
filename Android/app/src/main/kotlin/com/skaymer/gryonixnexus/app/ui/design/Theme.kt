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

/** Corner radii */
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

/** Material 3 type scale */
val GryonixTypography = Typography(
    displayLarge = sf(34, 42, FontWeight.Bold),
    displayMedium = sf(28, 36, FontWeight.Bold),
    displaySmall = sf(24, 32, FontWeight.SemiBold),
    headlineLarge = sf(32, 40, FontWeight.SemiBold),
    headlineMedium = sf(28, 36, FontWeight.SemiBold),
    headlineSmall = sf(22, 28, FontWeight.SemiBold),
    titleLarge = sf(22, 28, FontWeight.Medium),
    titleMedium = sf(16, 24, FontWeight.Medium, 0.15),
    titleSmall = sf(14, 20, FontWeight.Medium, 0.1),
    bodyLarge = sf(16, 24, tracking = 0.15),
    bodyMedium = sf(14, 20, tracking = 0.25),
    bodySmall = sf(12, 16, tracking = 0.4),
    labelLarge = sf(14, 20, FontWeight.Medium, 0.1),
    labelMedium = sf(12, 16, FontWeight.Medium, 0.5),
    labelSmall = sf(11, 16, FontWeight.Medium, 0.5),
)
