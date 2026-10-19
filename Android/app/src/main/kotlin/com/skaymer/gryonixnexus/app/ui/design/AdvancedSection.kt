package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R

@Composable
fun AdvancedSection(
    modifier: Modifier = Modifier,
    footer: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    GroupedSection(modifier = modifier, footer = footer?.takeIf { expanded }) {
        GroupedRow(
            onClick = { expanded = !expanded },
            showDivider = expanded,
            trailing = {
                Text(
                    if (expanded) "−" else "+",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.secondaryLabel,
                )
            },
        ) {
            Text(
                stringResource(R.string.advanced),
                style = MaterialTheme.typography.bodyLarge,
                color = Gryonix.colors.label,
                modifier = Modifier.weight(1f),
            )
        }
        if (expanded) content()
    }
}
