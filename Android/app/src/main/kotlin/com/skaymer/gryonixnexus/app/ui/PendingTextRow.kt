package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.ApplyPendingBar
import com.skaymer.gryonixnexus.app.ui.design.FieldRow

/** A text row whose edit waits in the bar */
@Composable
fun PendingTextRow(
    label: String,
    saved: String,
    onApply: (String) -> Unit,
    modifier: androidx.compose.ui.Modifier = androidx.compose.ui.Modifier,
    placeholder: String? = null,
    apply: String = stringResource(R.string.save),
    clearsAfterApply: Boolean = false,
    showDivider: Boolean = false,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    valid: (String) -> Boolean = { it.isNotBlank() },
) {
    var draft by remember(saved) { mutableStateOf(saved) }
    FieldRow(
        label = label,
        value = draft,
        onValueChange = { draft = it },
        modifier = modifier,
        placeholder = placeholder,
        showDivider = showDivider,
        keyboardOptions = keyboardOptions,
    )
    ApplyPendingBar(
        visible = draft.trim() != saved && valid(draft),
        apply = apply,
        cancel = stringResource(R.string.pending_changes_cancel),
        onApply = {
            onApply(draft)
            if (clearsAfterApply) draft = saved
        },
        onRevert = { draft = saved },
    )
}
