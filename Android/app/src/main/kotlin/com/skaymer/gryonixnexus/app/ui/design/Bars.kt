package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Flat bottom navigation bar, edge to edge */
@Composable
fun AppBottomBar(content: @Composable RowScope.() -> Unit) {
    val colors = Gryonix.colors
    Column(Modifier.fillMaxWidth().background(colors.barBackground)) {
        Separator()
        Row(
            Modifier.fillMaxWidth().height(BottomBarHeight),
            verticalAlignment = Alignment.CenterVertically,
            content = content,
        )
        Box(Modifier.fillMaxWidth().navigationBarsPadding())
    }
}

val BottomBarHeight = 64.dp

/** One destination: icon in a pill when selected, label below */
@Composable
fun RowScope.BottomBarItem(
    icon: ImageVector,
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val colors = Gryonix.colors
    val tint by animateColorAsState(if (selected) colors.accent else colors.secondaryLabel, label = "tint")
    val pill by animateColorAsState(
        if (selected) colors.accent.copy(alpha = 0.14f) else Color.Transparent,
        label = "pill",
    )
    Column(
        Modifier
            .weight(1f)
            .height(BottomBarHeight)
            .clickable(role = Role.Tab, onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
    ) {
        Box(
            Modifier.clip(RoundedCornerShape(16.dp)).background(pill)
                .padding(horizontal = 16.dp, vertical = 4.dp),
        ) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(24.dp))
        }
        Text(
            label,
            color = tint,
            fontSize = 11.sp,
            lineHeight = 16.sp,
            letterSpacing = 0.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
    }
}

/** iOS-style top bar: large title, or back and centered title */
@Composable
fun AppTopBar(
    title: String,
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
    /** The page scrolled: the large title shrinks to the middle */
    collapsed: Boolean = false,
    actions: @Composable RowScope.() -> Unit = {},
) {
    Column(modifier.fillMaxWidth().background(Gryonix.colors.groupedBackground)) {
        Box(Modifier.fillMaxWidth().statusBarsPadding())
        when {
            onBack != null -> InlineTitleBar(title, onBack, actions)
            collapsed -> InlineTitleBar(title, null, actions)
            else -> LargeTitleBar(title, actions)
        }
    }
}

/** Says when a scrolled page should shrink its large title */
class LargeTitleScroll : androidx.compose.ui.input.nestedscroll.NestedScrollConnection {
    private var offset by androidx.compose.runtime.mutableFloatStateOf(0f)

    val collapsed: Boolean get() = offset < -COLLAPSE_AFTER

    override fun onPostScroll(
        consumed: androidx.compose.ui.geometry.Offset,
        available: androidx.compose.ui.geometry.Offset,
        source: androidx.compose.ui.input.nestedscroll.NestedScrollSource,
    ): androidx.compose.ui.geometry.Offset {
        offset = (offset + consumed.y).coerceAtMost(0f)
        return androidx.compose.ui.geometry.Offset.Zero
    }

    fun reset() {
        offset = 0f
    }

    private companion object {
        const val COLLAPSE_AFTER = 80f
    }
}

/** A root screen: big bold title on the left */
@Composable
private fun LargeTitleBar(title: String, actions: @Composable RowScope.() -> Unit) {
    Row(
        Modifier.fillMaxWidth().height(72.dp).padding(start = 20.dp, end = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            title,
            color = Gryonix.colors.label,
            fontSize = 32.sp,
            lineHeight = 38.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically, content = actions)
    }
}

/** A pushed screen: round back button, title in the middle */
@Composable
private fun InlineTitleBar(title: String, onBack: (() -> Unit)?, actions: @Composable RowScope.() -> Unit) {
    Box(Modifier.fillMaxWidth().height(64.dp).padding(horizontal = 12.dp)) {
        if (onBack != null) {
            BarIconButton(onClick = onBack, modifier = Modifier.align(Alignment.CenterStart)) {
                Icon(Icons.AutoMirrored.Filled.ArrowBackIos, contentDescription = null, modifier = Modifier.size(20.dp).padding(start = 4.dp))
            }
        }
        Text(
            title,
            color = Gryonix.colors.label,
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
            modifier = Modifier.align(Alignment.Center).padding(horizontal = 112.dp),
        )
        Row(
            Modifier.align(Alignment.CenterEnd),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = actions,
        )
    }
}

/** A round 44dp top bar button */
@Composable
fun BarIconButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable () -> Unit,
) {
    val colors = Gryonix.colors
    IconButton(
        onClick = onClick,
        modifier = modifier
            .size(44.dp)
            .shadow(1.dp, CircleShape, ambientColor = colors.separator, spotColor = colors.separator)
            .border(0.5.dp, colors.separator.copy(alpha = 0.15f), CircleShape),
        enabled = enabled,
        colors = IconButtonDefaults.iconButtonColors(
            containerColor = colors.cardBackground,
            contentColor = colors.label,
            disabledContainerColor = colors.cardBackground,
            disabledContentColor = colors.tertiaryLabel,
        ),
        content = content,
    )
}
