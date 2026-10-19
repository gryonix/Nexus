package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** The iPhone's tab bar — the FLOATING one */
@Composable
fun IOSTabBar(content: @Composable RowScope.() -> Unit) {
    val colors = Gryonix.colors
    Column(
        Modifier
            .fillMaxWidth()
            .background(colors.groupedBackground)
            .padding(horizontal = TabBarSideInset, vertical = TabBarFloatInset),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .height(TabBarHeight)
                .shadow(TabBarShadow, TabBarShape, clip = false)
                .clip(TabBarShape)
                .background(colors.barBackground)
                .border(0.5.dp, colors.separator.copy(alpha = 0.35f), TabBarShape)
                .padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = content,
        )
        Box(Modifier.fillMaxWidth().navigationBarsPadding())
    }
}

/** 56dp, not the 49pt the old bar had */
val TabBarHeight = 56.dp

/** How far the capsule stands in from the screen's edges */
val TabBarSideInset = 12.dp

/** And off the bottom, above the gesture area */
val TabBarFloatInset = 8.dp

/** Half the height: a capsule, not a rounded rectangle */
val TabBarShape = RoundedCornerShape(TabBarHeight / 2)

/** Soft and short */
val TabBarShadow = 8.dp

@Composable
fun RowScope.IOSTabItem(
    icon: ImageVector,
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val colors = Gryonix.colors
    val tint = if (selected) colors.accent else colors.secondaryLabel
    val interaction = remember { MutableInteractionSource() }
    Column(
        Modifier
            .weight(1f)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically),
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(26.dp))
        Text(
            label,
            color = tint,
            fontSize = 10.sp,
            lineHeight = 12.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
    }
}

/** A navigation bar in the iPhone's two shapes */
@Composable
fun IOSNavBar(
    title: String,
    modifier: Modifier = Modifier,
    large: Boolean = false,
    onBack: (() -> Unit)? = null,
    /** What the bar carries on the right */
    actions: @Composable RowScope.() -> Unit = {},
) {
    val colors = Gryonix.colors
    Column(modifier.fillMaxWidth().background(colors.barBackground)) {
        Box(Modifier.fillMaxWidth().statusBarsPadding())
        Row(
            Modifier.fillMaxWidth().height(if (large) 52.dp else 44.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onBack != null) {
                IOSBarButton(onClick = onBack) {
                    Icon(
                        Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                        contentDescription = null,
                        modifier = Modifier.size(28.dp),
                    )
                }
            } else {
                Box(Modifier.width(Metrics.rowInset))
            }
            Text(
                title,
                style = if (large) {
                    MaterialTheme.typography.displaySmall
                } else {
                    MaterialTheme.typography.titleMedium
                },
                color = colors.label,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = if (large) TextAlign.Start else TextAlign.Center,
                modifier = Modifier.weight(1f),
            )
            CompositionLocalProvider(LocalContentColor provides colors.accent) {
                Row(
                    Modifier.padding(end = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                    content = actions,
                )
                if (!large && onBack != null) Box(Modifier.width(6.dp))
            }
        }
    }
}

@Composable
fun IOSBarButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable () -> Unit,
) {
    val colors = Gryonix.colors
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier
            .size(44.dp)
            .clickable(
                enabled = enabled,
                interactionSource = interaction,
                indication = null,
                onClick = onClick,
            ),
        contentAlignment = Alignment.Center,
    ) {
        CompositionLocalProvider(
            LocalContentColor provides if (enabled) colors.accent else colors.tertiaryLabel,
            content = content,
        )
    }
}
