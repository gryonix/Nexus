package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert

/** Asks for a wait in seconds within a range */
@Composable
fun CustomSecondsAlert(title: String, range: IntRange, onSet: (Int) -> Unit, onDismiss: () -> Unit) {
    var text by remember { mutableStateOf("") }
    val seconds = text.trim().toIntOrNull()?.takeIf { it in range }
    IOSAlert(
        title = title,
        message = stringResource(R.string.connection_seconds_range, range.first, range.last),
        onDismiss = onDismiss,
        actions = listOf(
            AlertAction(stringResource(R.string.close)) { onDismiss() },
            AlertAction(stringResource(R.string.swap_set), preferred = true, enabled = seconds != null) {
                seconds?.let(onSet)
                onDismiss()
            },
        ),
    ) {
        FieldRow(
            label = stringResource(R.string.connection_seconds),
            value = text,
            onValueChange = { value -> text = value.filter(Char::isDigit).take(5) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            showDivider = false,
        )
    }
}
