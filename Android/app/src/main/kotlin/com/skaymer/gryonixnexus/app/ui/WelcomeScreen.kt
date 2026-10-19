package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.ProminentButton
import com.skaymer.gryonixnexus.R

/** What this app is, said once, on the first launch */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WelcomeSheet(onConfigure: () -> Unit, onDismiss: () -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = state,
        containerColor = Gryonix.colors.cardBackground,
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
        dragHandle = null,
    ) {
        Column(
            Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(top = 32.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    stringResource(R.string.welcome_title),
                    style = MaterialTheme.typography.displayLarge,
                    color = Gryonix.colors.label,
                )
                Text(
                    stringResource(R.string.welcome_subtitle),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.secondaryLabel,
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Point(Icons.Filled.Build, R.string.welcome_builds_title, R.string.welcome_builds_detail)
                Point(Icons.Filled.Info, R.string.welcome_watches_title, R.string.welcome_watches_detail)
                Point(Icons.Filled.Lock, R.string.welcome_yours_title, R.string.welcome_yours_detail)
            }

            Column(
                Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                ProminentButton(
                    text = stringResource(R.string.welcome_configure),
                    onClick = onConfigure,
                )
                PlainButton(
                    text = stringResource(R.string.welcome_look_around),
                    onClick = onDismiss,
                )
            }

            Text(
                stringResource(R.string.welcome_demo_note),
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.tertiaryLabel,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun Point(icon: ImageVector, title: Int, detail: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Icon(
            icon,
            contentDescription = null,
            tint = Gryonix.colors.accent,
            modifier = Modifier.width(34.dp).size(30.dp),
        )
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                stringResource(title),
                style = MaterialTheme.typography.titleLarge,
                color = Gryonix.colors.label,
            )
            Text(
                stringResource(detail),
                style = MaterialTheme.typography.bodyMedium,
                color = Gryonix.colors.secondaryLabel,
            )
        }
    }
}
