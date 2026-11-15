package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.ServerIcons
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.SymbolIcons

/** The server icons as tappable tiles; null is the default */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ServerIconPicker(chosen: String?, tint: Color, modifier: Modifier = Modifier, onChoose: (String?) -> Unit) {
    FlowRow(
        modifier,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        IconTile(null, chosen == null, tint, onChoose)
        ServerIcons.choices.forEach { IconTile(it, chosen == it, tint, onChoose) }
    }
}

@Composable
private fun IconTile(symbol: String?, selected: Boolean, tint: Color, onChoose: (String?) -> Unit) {
    val label = symbol ?: stringResource(R.string.tint_default)
    Box(
        Modifier
            .size(34.dp)
            .clip(RoundedCornerShape(9.dp))
            .background(if (selected) tint else Gryonix.colors.secondaryLabel.copy(alpha = 0.14f))
            .clickable(role = Role.Button) { onChoose(symbol) }
            .semantics { this.selected = selected; this.contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            SymbolIcons.of(symbol ?: ServerIcons.DEFAULT), contentDescription = null,
            tint = if (selected) Color.White else tint, modifier = Modifier.size(18.dp),
        )
    }
}
