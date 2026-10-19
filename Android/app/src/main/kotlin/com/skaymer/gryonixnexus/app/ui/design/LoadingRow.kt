package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R

/** A small spinner with "Loading…", inset like a list row. */
@Composable
fun LoadingRow() {
    Row(
        Modifier.padding(horizontal = Metrics.listInset + 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CircularProgressIndicator(
            Modifier.size(16.dp),
            strokeWidth = 2.dp,
            color = Gryonix.colors.tertiaryLabel,
        )
        Text(
            stringResource(R.string.backups_loading),
            style = MaterialTheme.typography.bodyMedium,
            color = Gryonix.colors.secondaryLabel,
        )
    }
}
