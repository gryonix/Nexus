package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import com.skaymer.gryonixnexus.app.shell.Haptics
import androidx.compose.ui.unit.dp

/** The numbers the iPhone's grouped screens are laid out on */
object Metrics {
    val listInset = 16.dp
    /** Inside a row, from its own edge to its text */
    val rowInset = 16.dp
    /** The shortest a tappable row is allowed to be */
    val rowHeight = 44.dp
    /** A grouped block's corner */
    val blockCorner = 10.dp
    /** A card's corner — `GlassCardSurface.defaultCornerRadius` on the other side */
    val cardCorner = 16.dp
    /** Between one block and the next */
    val sectionGap = 24.dp
}

/** A card's surface, drawn in solid colour */
fun Modifier.cardSurface(
    color: Color,
    tint: Color? = null,
    corner: Dp = Metrics.cardCorner,
): Modifier {
    val shape = RoundedCornerShape(corner)
    return clip(shape)
        .background(color, shape)
        .then(if (tint != null) Modifier.background(tint.copy(alpha = 0.12f), shape) else Modifier)
        .then(
            if (tint != null) Modifier.border(1.dp, tint.copy(alpha = 0.35f), shape)
            else Modifier
        )
}

@Composable
fun CardSurface(
    modifier: Modifier = Modifier,
    tint: Color? = null,
    corner: Dp = Metrics.cardCorner,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier.cardSurface(Gryonix.colors.cardBackground, tint, corner),
        content = content,
    )
}

@Composable
fun GroupedSection(
    modifier: Modifier = Modifier,
    header: String? = null,
    footer: String? = null,
    note: String? = null,
    dividerInset: Dp = Metrics.rowInset,
    /** A small circular arrow in the header */
    onRefresh: (() -> Unit)? = null,
    refreshDescription: String = "",
    refreshing: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = Gryonix.colors
    Column(modifier.fillMaxWidth()) {
        if (header != null) {
            if (note != null) {
                InfoSectionHeader(
                    title = header,
                    note = note,
                    onRefresh = onRefresh,
                    refreshDescription = refreshDescription,
                    refreshing = refreshing,
                )
            } else if (onRefresh != null) {
                Row(
                    Modifier.fillMaxWidth().padding(end = Metrics.listInset),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SectionHeader(header, Modifier.weight(1f))
                    RefreshButton(
                        contentDescription = refreshDescription,
                        onClick = onRefresh,
                        busy = refreshing,
                    )
                }
            } else {
                SectionHeader(header)
            }
        }
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = Metrics.listInset)
                .clip(RoundedCornerShape(Metrics.blockCorner))
                .background(colors.cardBackground),
        ) {
            SeparatedColumn(inset = dividerInset, content = content)
        }
        if (footer != null) {
            Text(
                footer,
                style = MaterialTheme.typography.bodySmall,
                color = colors.secondaryLabel,
                modifier = Modifier.padding(
                    start = Metrics.listInset + 4.dp,
                    end = Metrics.listInset + 4.dp,
                    top = 6.dp,
                ),
            )
        }
    }
}

/** A grouped section's own heading, on its own */
@Composable
fun SectionHeader(text: String, modifier: Modifier = Modifier) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.bodySmall,
        color = Gryonix.colors.secondaryLabel,
        modifier = modifier.padding(
            start = Metrics.listInset + 4.dp,
            end = Metrics.listInset + 4.dp,
            bottom = 6.dp,
        ),
    )
}

@Composable
private fun SeparatedColumn(
    inset: Dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    CompositionLocalProvider(LocalRowDividerInset provides inset) {
        Column(Modifier.fillMaxWidth(), content = content)
    }
}

internal val LocalRowDividerInset = androidx.compose.runtime.compositionLocalOf { Metrics.rowInset }

@Composable
fun GroupedRow(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    /** Press and hold */
    onLongClick: (() -> Unit)? = null,
    /** What the press feels like — see `Haptics` */
    feel: Haptics.Feel = Haptics.Feel.TAP,
    showDivider: Boolean = true,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
    content: @Composable RowScope.() -> Unit,
) {
    val colors = Gryonix.colors
    val inset = LocalRowDividerInset.current
    val haptics = LocalHaptics.current
    Column(modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .then(
                    if (onClick != null || onLongClick != null) {
                        Modifier.combinedClickable(
                            onClick = { onClick?.let { haptics(feel); it() } },
                            onLongClick = onLongClick?.let { hold ->
                                { haptics(Haptics.Feel.TAP); hold() }
                            },
                        )
                    } else Modifier
                )
                .defaultMinSize(minHeight = Metrics.rowHeight)
                .padding(horizontal = Metrics.rowInset, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (leading != null) {
                CompositionLocalProvider(LocalContentColor provides colors.accent) { leading() }
            }
            content()
            if (trailing != null) {
                CompositionLocalProvider(LocalContentColor provides colors.secondaryLabel) {
                    trailing()
                }
            }
        }
        if (showDivider) Separator(startInset = inset)
    }
}

/** The hairline */
@Composable
fun Separator(modifier: Modifier = Modifier, startInset: Dp = 0.dp) {
    Box(
        modifier
            .fillMaxWidth()
            .padding(start = startInset)
            .height(0.5.dp)
            .background(Gryonix.colors.separator),
    )
}

/** The page a grouped screen stands on */
@Composable
fun GroupedBackground(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Box(modifier.background(Gryonix.colors.groupedBackground)) { content() }
}

/** The padding a scrolling grouped screen puts around its blocks */
val GroupedContentPadding = PaddingValues(top = 16.dp, bottom = 32.dp)

/** Between blocks in a scrolling grouped screen */
val GroupedSpacing = Arrangement.spacedBy(Metrics.sectionGap)

val BlockShape: Shape = RoundedCornerShape(Metrics.blockCorner)
