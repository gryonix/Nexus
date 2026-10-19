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
import com.skaymer.gryonixnexus.catalog.storage.SwapPlan

/** Asks for a swap size in whole gigabytes */
@Composable
fun CustomSwapSizeAlert(onSet: (Int) -> Unit, onDismiss: () -> Unit) {
    var text by remember { mutableStateOf("") }
    val size = text.trim().toIntOrNull()?.takeIf { it in SwapPlan.ALLOWED }
    IOSAlert(
        title = stringResource(R.string.swap_custom_title),
        message = stringResource(R.string.swap_custom_note),
        onDismiss = onDismiss,
        actions = listOf(
            AlertAction(stringResource(R.string.close)) { onDismiss() },
            AlertAction(stringResource(R.string.swap_set), preferred = true, enabled = size != null) {
                size?.let(onSet)
                onDismiss()
            },
        ),
    ) {
        FieldRow(
            label = "GB",
            value = text,
            onValueChange = { value -> text = value.filter(Char::isDigit).take(3) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            showDivider = false,
        )
    }
}
