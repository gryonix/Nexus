package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.shell.AppIcon
import com.skaymer.gryonixnexus.app.shell.AppIcons
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix

/** Picks the home-screen icon colour */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AppIconPicker() {
    val context = LocalContext.current
    var current by remember { mutableStateOf(AppIcons.current(context)) }
    GroupedSection(
        header = stringResource(R.string.settings_app_icon),
        note = stringResource(R.string.settings_app_icon_footer),
    ) {
        FlowRow(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            AppIcon.entries.forEach { icon ->
                IconTile(icon, selected = icon == current) {
                    AppIcons.choose(context, icon)
                    current = icon
                }
            }
        }
    }
}

@Composable
private fun IconTile(icon: AppIcon, selected: Boolean, onPick: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.clickable(onClick = onPick),
    ) {
        Image(
            painter = painterResource(icon.previewRes),
            contentDescription = stringResource(icon.labelRes),
            modifier = Modifier
                .size(60.dp)
                .clip(shape)
                .border(if (selected) 3.dp else 0.5.dp,
                    if (selected) Gryonix.colors.accent else Gryonix.colors.separator, shape),
        )
        Text(
            stringResource(icon.labelRes),
            style = MaterialTheme.typography.labelSmall,
            color = if (selected) Gryonix.colors.label else Gryonix.colors.secondaryLabel,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}

private val AppIcon.labelRes: Int
    get() = when (this) {
        AppIcon.BLUE -> R.string.tint_blue
        AppIcon.RED -> R.string.tint_red
        AppIcon.ORANGE -> R.string.tint_orange
        AppIcon.YELLOW -> R.string.accent_yellow
        AppIcon.GREEN -> R.string.tint_green
        AppIcon.TEAL -> R.string.tint_teal
        AppIcon.PURPLE -> R.string.tint_purple
        AppIcon.PINK -> R.string.tint_pink
        AppIcon.GRAPHITE -> R.string.accent_graphite
        AppIcon.BLACK -> R.string.accent_black
        AppIcon.INDIGO -> R.string.accent_indigo
        AppIcon.BROWN -> R.string.accent_brown
    }

private val AppIcon.previewRes: Int
    get() = when (this) {
        AppIcon.BLUE -> R.drawable.icon_preview_blue
        AppIcon.RED -> R.drawable.icon_preview_red
        AppIcon.ORANGE -> R.drawable.icon_preview_orange
        AppIcon.YELLOW -> R.drawable.icon_preview_yellow
        AppIcon.GREEN -> R.drawable.icon_preview_green
        AppIcon.TEAL -> R.drawable.icon_preview_teal
        AppIcon.PURPLE -> R.drawable.icon_preview_purple
        AppIcon.PINK -> R.drawable.icon_preview_pink
        AppIcon.GRAPHITE -> R.drawable.icon_preview_graphite
        AppIcon.BLACK -> R.drawable.icon_preview_black
        AppIcon.INDIGO -> R.drawable.icon_preview_indigo
        AppIcon.BROWN -> R.drawable.icon_preview_brown
    }
