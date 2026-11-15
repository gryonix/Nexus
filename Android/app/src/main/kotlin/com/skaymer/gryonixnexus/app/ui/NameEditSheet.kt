package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet

/** A sheet with one name row */
@Composable
fun NameEditSheet(
    title: String,
    label: String,
    initial: String,
    onSave: (String) -> Unit,
    onClose: () -> Unit,
    valid: (String) -> Boolean = { it.isNotBlank() },
) {
    IOSSheet(title = title, onClose = onClose, closeLabel = stringResource(R.string.close)) {
        GroupedSection {
            PendingTextRow(
                label = label,
                saved = initial,
                valid = valid,
                onApply = { onSave(it); onClose() },
            )
        }
    }
}
