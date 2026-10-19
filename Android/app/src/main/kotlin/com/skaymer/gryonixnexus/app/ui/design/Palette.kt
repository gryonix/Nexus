package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

@Immutable
data class GryonixColors(
    /** Behind a grouped list — the page itself, never a card */
    val groupedBackground: Color,
    /** A card, and a row inside a grouped list */
    val cardBackground: Color,
    /** Behind a plain (ungrouped) screen */
    val background: Color,
    /** Bars: the tab bar and the navigation bar */
    val barBackground: Color,
    /** The hairline under a bar and between two rows */
    val separator: Color,
    val label: Color,
    val secondaryLabel: Color,
    val tertiaryLabel: Color,
    /** The fill behind a segmented control's track */
    val trackFill: Color,
    /** The sliding thumb that marks the chosen segment */
    val thumbFill: Color,
    val accent: Color,
    val danger: Color,
    val success: Color,
    val warning: Color,
    val isDark: Boolean,
)

/** Light */
val LightColors = GryonixColors(
    groupedBackground = Color(0xFFF2F2F7),
    cardBackground = Color(0xFFFFFFFF),
    background = Color(0xFFFFFFFF),
    barBackground = Color(0xFFF9F9F9),
    separator = Color(0x5C3C3C43),
    label = Color(0xFF000000),
    secondaryLabel = Color(0x993C3C43),
    tertiaryLabel = Color(0x4D3C3C43),
    trackFill = Color(0x1E787880),
    thumbFill = Color(0xFFFFFFFF),
    accent = Color(0xFF007AFF),
    danger = Color(0xFFFF3B30),
    success = Color(0xFF34C759),
    warning = Color(0xFFFF9500),
    isDark = false,
)

/** Dark */
val DarkColors = GryonixColors(
    groupedBackground = Color(0xFF000000),
    cardBackground = Color(0xFF1C1C1E),
    background = Color(0xFF000000),
    barBackground = Color(0xFF1D1D1D),
    separator = Color(0xA6545458),
    label = Color(0xFFFFFFFF),
    secondaryLabel = Color(0x99EBEBF5),
    tertiaryLabel = Color(0x4DEBEBF5),
    trackFill = Color(0x5C787880),
    thumbFill = Color(0xFF636366),
    accent = Color(0xFF0A84FF),
    danger = Color(0xFFFF453A),
    success = Color(0xFF30D158),
    warning = Color(0xFFFF9F0A),
    isDark = true,
)

/** Read as `Gryonix.colors` from anywhere in the tree */
val LocalGryonixColors = staticCompositionLocalOf { LightColors }
