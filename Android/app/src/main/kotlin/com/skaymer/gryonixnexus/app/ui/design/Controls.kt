package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.ui.draw.shadow
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Spacer
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.border
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Remove
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.shell.Haptics
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

@Composable
fun <T> IOSSegmentedControl(
    segments: List<T>,
    selected: T,
    modifier: Modifier = Modifier,
    scrollable: Boolean = segments.size > 4,
    label: @Composable (T) -> String,
    onSelect: (T) -> Unit,
    /** Held rather than tapped */
    onLongPress: ((T) -> Unit)? = null,
) {
    if (segments.isEmpty()) return
    val colors = Gryonix.colors
    val density = LocalDensity.current
    val bounds = remember(segments) { mutableStateMapOf<Int, Pair<Float, Float>>() }
    val index = segments.indexOf(selected).coerceAtLeast(0)
    val target = bounds[index]
    val x by animateFloatAsState(target?.first ?: 0f, tween(220), label = "thumbX")
    val width by animateFloatAsState(target?.second ?: 0f, tween(220), label = "thumbW")

    val row: @Composable () -> Unit = {
        Row(Modifier.height(SegmentedHeight - 4.dp)) {
            segments.forEachIndexed { position, segment ->
                val isSelected = segment == selected
                val interaction = remember { MutableInteractionSource() }
                Box(
                    Modifier
                        .then(if (scrollable) Modifier else Modifier.weight(1f))
                        .fillMaxHeight()
                        .onGloballyPositioned {
                            bounds[position] = it.positionInParent().x to it.size.width.toFloat()
                        }
                        .combinedClickable(
                            interactionSource = interaction,
                            indication = null,
                            onClick = { onSelect(segment) },
                            onLongClick = onLongPress?.let { press -> { press(segment) } },
                        )
                        .padding(horizontal = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        label(segment),
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                        color = colors.label,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }

    Box(
        modifier
            .then(if (scrollable) Modifier else Modifier.fillMaxWidth())
            .height(SegmentedHeight)
            .clip(RoundedCornerShape(9.dp))
            .background(colors.trackFill)
            .padding(2.dp),
    ) {
        Box(
            Modifier
                .offset { IntOffset(x.roundToInt(), 0) }
                .width(with(density) { width.toDp() })
                .fillMaxHeight()
                .clip(RoundedCornerShape(7.dp))
                .background(colors.thumbFill),
        )
        if (scrollable) {
            Box(Modifier.horizontalScroll(rememberScrollState())) { row() }
        } else {
            row()
        }
    }
}

/** 32pt is the height Apple's segmented control comes in */
val SegmentedHeight = 32.dp

@Composable
fun ProminentButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    danger: Boolean = false,
) {
    val colors = Gryonix.colors
    val haptics = LocalHaptics.current
    Button(
        onClick = {
            haptics(if (danger) Haptics.Feel.WEIGHTY else Haptics.Feel.TAP)
            onClick()
        },
        enabled = enabled,
        modifier = modifier.fillMaxWidth().height(48.dp),
        shape = RoundedCornerShape(percent = 50),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (danger) colors.danger else colors.accent,
            contentColor = Color.White,
            disabledContainerColor = colors.trackFill,
            disabledContentColor = colors.tertiaryLabel,
        ),
    ) {
        Text(text, style = MaterialTheme.typography.labelLarge)
    }
}

@Composable
fun PlainButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    danger: Boolean = false,
) {
    val colors = Gryonix.colors
    val haptics = LocalHaptics.current
    TextButton(
        onClick = {
            haptics(if (danger) Haptics.Feel.WEIGHTY else Haptics.Feel.TAP)
            onClick()
        },
        enabled = enabled,
        modifier = modifier,
    ) {
        Text(
            text,
            style = MaterialTheme.typography.bodyLarge,
            color = when {
                !enabled -> colors.tertiaryLabel
                danger -> colors.danger
                else -> colors.accent
            },
        )
    }
}

@Composable
fun ActionRow(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    danger: Boolean = false,
    showDivider: Boolean = true,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
) {
    val colors = Gryonix.colors
    GroupedRow(
        modifier = modifier,
        onClick = if (enabled) onClick else null,
        feel = if (danger) Haptics.Feel.WEIGHTY else Haptics.Feel.TAP,
        showDivider = showDivider,
        leading = leading,
        trailing = trailing,
    ) {
        Text(
            text,
            style = MaterialTheme.typography.bodyLarge,
            color = when {
                !enabled -> colors.tertiaryLabel
                danger -> colors.danger
                else -> colors.accent
            },
        )
    }
}

@Composable
fun RowScope.RowLabel(
    title: String,
    subtitle: String? = null,
) {
    val colors = Gryonix.colors
    Column(
        Modifier.weight(1f),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(title, style = MaterialTheme.typography.bodyLarge, color = colors.label)
        if (subtitle != null) {
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = colors.secondaryLabel)
        }
    }
}

/** The chevron that says a row opens something */
@Composable
fun DisclosureChevron() {
    Icon(
        Icons.AutoMirrored.Filled.KeyboardArrowRight,
        contentDescription = null,
        tint = Gryonix.colors.tertiaryLabel,
        modifier = Modifier.size(22.dp),
    )
}

/** Material switch in the app accent */
@Composable
fun IOSSwitch(
    checked: Boolean,
    onCheckedChange: ((Boolean) -> Unit)?,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onColor: Color? = null,
) {
    val colors = Gryonix.colors
    val haptics = LocalHaptics.current
    val track = onColor ?: colors.accent
    Switch(
        checked = checked,
        onCheckedChange = onCheckedChange?.let { change ->
            { value: Boolean ->
                haptics(if (value) Haptics.Feel.SUCCESS else Haptics.Feel.TAP)
                change(value)
            }
        },
        enabled = enabled,
        modifier = modifier,
        // A thumb with content keeps one size, as on iOS.
        thumbContent = { Box(Modifier.size(SwitchDefaults.IconSize)) },
        colors = SwitchDefaults.colors(
            checkedThumbColor = Color.White,
            checkedTrackColor = track,
            checkedBorderColor = track,
            uncheckedThumbColor = Color.White,
            uncheckedTrackColor = colors.trackFill.copy(alpha = maxOf(colors.trackFill.alpha, 0.28f)),
            uncheckedBorderColor = Color.Transparent,
        ),
    )
}

@Composable
fun ValueRow(
    title: String,
    value: String?,
    onClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    showDivider: Boolean = true,
    leading: (@Composable () -> Unit)? = null,
    /** What a tappable row shows at its end */
    chevron: @Composable () -> Unit = { DisclosureChevron() },
    valueColor: Color = Gryonix.colors.secondaryLabel,
    /** Longer explanation behind an "i" at the row's end */
    infoNote: String? = null,
) {
    val colors = Gryonix.colors
    val style = MaterialTheme.typography.bodyLarge
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    BoxWithConstraints(modifier) {
        val needed = with(density) {
            (measurer.measure(title, style).size.width + measurer.measure(value.orEmpty(), style).size.width).toDp()
        }
        val chrome = ROW_CHROME + if (leading != null) LEADING_WIDTH else 0.dp
        val oneLine = value == null || needed + chrome <= maxWidth
        GroupedRow(
            onClick = onClick,
            showDivider = showDivider,
            leading = leading,
            trailing = {
                if (infoNote != null) InfoNoteButton(title = title, note = infoNote)
                if (value != null && oneLine) {
                    Text(value, style = style, color = valueColor, maxLines = 1)
                }
                if (onClick != null) chevron()
            },
        ) {
            if (oneLine) RowLabel(title, subtitle) else RowLabel(title, listOfNotNull(value, subtitle).joinToString("\n"))
        }
    }
}

/** Insets, gap and chevron around a one-line row */
private val ROW_CHROME = 64.dp

/** Room a leading icon takes */
private val LEADING_WIDTH = 40.dp

@Composable
fun ToggleRow(
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    enabled: Boolean = true,
    showDivider: Boolean = true,
    /** Longer explanation behind an "i" beside the switch */
    infoNote: String? = null,
) {
    GroupedRow(
        modifier = modifier,
        showDivider = showDivider,
        trailing = {
            if (infoNote != null) InfoNoteButton(title = title, note = infoNote)
            IOSSwitch(checked = checked, onCheckedChange = onCheckedChange, enabled = enabled)
        },
    ) {
        RowLabel(title, subtitle)
    }
}

@Composable
fun FieldRow(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String? = null,
    showDivider: Boolean = true,
    singleLine: Boolean = true,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    /** Longer explanation behind an "i" at the row's end */
    infoNote: String? = null,
) {
    val colors = Gryonix.colors
    val style = MaterialTheme.typography.bodyLarge
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    GroupedRow(
        modifier = modifier,
        showDivider = showDivider,
        trailing = { if (infoNote != null) InfoNoteButton(title = label, note = infoNote) },
    ) {
        BoxWithConstraints(Modifier.weight(1f)) {
            val labelWidth = with(density) { measurer.measure(label, style).size.width.toDp() }
            val input: @Composable (TextAlign, Modifier) -> Unit = { align, fieldModifier ->
                FieldInput(value, onValueChange, placeholder ?: label, align, singleLine, keyboardOptions,
                    visualTransformation, keyboardActions, fieldModifier)
            }
            if (labelWidth + FIELD_GAP + FIELD_MIN <= maxWidth) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(label, style = style, color = colors.label, maxLines = 1)
                    Spacer(Modifier.width(FIELD_GAP))
                    input(TextAlign.End, Modifier.weight(1f))
                }
            } else {
                Column {
                    Text(label, style = style, color = colors.label)
                    Spacer(Modifier.height(4.dp))
                    input(TextAlign.Start, Modifier.fillMaxWidth())
                }
            }
        }
    }
}

private val FIELD_GAP = 12.dp
private val FIELD_MIN = 100.dp

@Composable
private fun FieldInput(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    align: TextAlign,
    singleLine: Boolean,
    keyboardOptions: KeyboardOptions,
    visualTransformation: VisualTransformation,
    keyboardActions: KeyboardActions,
    modifier: Modifier,
) {
    val colors = Gryonix.colors
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        singleLine = singleLine,
        keyboardOptions = keyboardOptions,
        keyboardActions = keyboardActions,
        visualTransformation = visualTransformation,
        textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.label, textAlign = align),
        cursorBrush = SolidColor(colors.accent),
        modifier = modifier,
        decorationBox = { field ->
            Box(contentAlignment = if (align == TextAlign.End) Alignment.CenterEnd else Alignment.CenterStart) {
                if (value.isEmpty()) {
                    Text(
                        placeholder,
                        style = MaterialTheme.typography.bodyLarge,
                        color = colors.tertiaryLabel,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                field()
            }
        },
    )
}

@Composable
fun CheckRow(
    title: String,
    checked: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    showDivider: Boolean = true,
    leading: (@Composable () -> Unit)? = null,
) {
    GroupedRow(
        modifier = modifier,
        onClick = onClick,
        showDivider = showDivider,
        leading = leading,
        trailing = {
            if (checked) {
                Icon(
                    Icons.Filled.Check,
                    contentDescription = null,
                    tint = Gryonix.colors.accent,
                    modifier = Modifier.size(20.dp),
                )
            }
        },
    ) {
        RowLabel(title, subtitle)
    }
}

@Composable
fun CapsuleToggle(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = Gryonix.colors
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        color = if (selected) Color.White else colors.label,
        maxLines = 1,
        modifier = modifier
            .clip(RoundedCornerShape(percent = 50))
            .background(if (selected) colors.accent else colors.trackFill)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    )
}

@Composable
fun StepperRow(
    label: String,
    value: Int,
    range: IntRange,
    onChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
    showDivider: Boolean = true,
    format: (Int) -> String = { it.toString() },
    /** Longer explanation behind an "i" before the value */
    infoNote: String? = null,
) {
    val colors = Gryonix.colors
    GroupedRow(
        modifier = modifier,
        showDivider = showDivider,
        trailing = {
            if (infoNote != null) InfoNoteButton(title = label, note = infoNote)
            Text(
                format(value),
                style = MaterialTheme.typography.bodyLarge,
                color = colors.secondaryLabel,
                modifier = Modifier.widthIn(min = 32.dp),
                textAlign = TextAlign.End,
            )
            Row(
                Modifier
                    .clip(RoundedCornerShape(7.dp))
                    .background(colors.trackFill)
                    .height(30.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                StepperHalf(
                    icon = Icons.Filled.Remove,
                    description = stringResource(R.string.stepper_decrease, label),
                    enabled = value > range.first,
                ) { onChange((value - 1).coerceIn(range)) }
                Box(
                    Modifier
                        .width(0.5.dp)
                        .height(18.dp)
                        .background(colors.separator),
                )
                StepperHalf(
                    icon = Icons.Filled.Add,
                    description = stringResource(R.string.stepper_increase, label),
                    enabled = value < range.last,
                ) { onChange((value + 1).coerceIn(range)) }
            }
        },
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodyLarge,
            color = colors.label,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun StepperHalf(
    icon: ImageVector,
    description: String,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    val colors = Gryonix.colors
    Box(
        Modifier
            .width(40.dp)
            .fillMaxHeight()
            .then(if (enabled) Modifier.clickable(onClick = onClick) else Modifier)
            .semantics { role = Role.Button },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon,
            contentDescription = description,
            tint = if (enabled) colors.label else colors.tertiaryLabel,
            modifier = Modifier.size(18.dp),
        )
    }
}

/** One action of a `TileActionGroup` */
data class TileAction(
    val title: String,
    val icon: ImageVector,
    val onClick: () -> Unit,
    val enabled: Boolean = true,
    val danger: Boolean = false,
)

@Composable
fun TileActionGroup(actions: List<TileAction>, modifier: Modifier = Modifier) {
    val rows = remember(actions) {
        if (actions.size <= 3) {
            if (actions.isEmpty()) emptyList() else listOf(actions)
        } else {
            actions.chunked(2)
        }
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { action ->
                    TileActionButton(action, Modifier.weight(1f))
                }
            }
        }
    }
}

/** The tile itself */
@Composable
private fun TileActionButton(action: TileAction, modifier: Modifier = Modifier) {
    val colors = Gryonix.colors
    val haptics = LocalHaptics.current
    val ink = when {
        !action.enabled -> colors.tertiaryLabel
        action.danger -> colors.danger
        else -> colors.accent
    }
    val shape = RoundedCornerShape(28.dp)
    Column(
        modifier
            .defaultMinSize(minHeight = 72.dp)
            .shadow(1.dp, shape, ambientColor = colors.separator, spotColor = colors.separator)
            .clip(shape)
            .background(colors.cardBackground)
            .border(0.5.dp, colors.separator.copy(alpha = 0.25f), shape)
            .clickable(enabled = action.enabled) {
                haptics(if (action.danger) Haptics.Feel.WEIGHTY else Haptics.Feel.TAP)
                action.onClick()
            }
            .padding(vertical = 10.dp, horizontal = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
    ) {
        Icon(action.icon, contentDescription = null, tint = ink, modifier = Modifier.size(22.dp))
        Text(
            action.title,
            style = MaterialTheme.typography.labelSmall,
            color = ink,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
