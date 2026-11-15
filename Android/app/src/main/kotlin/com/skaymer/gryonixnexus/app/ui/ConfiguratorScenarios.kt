package com.skaymer.gryonixnexus.app.ui

import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Autorenew
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.DeviceHub
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Hub
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.app.configurator.ScenarioIcon
import com.skaymer.gryonixnexus.app.configurator.ScenarioOption
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix

/** The configurator's first screen: how is this server reached? */
@Composable
fun ConfiguratorScenariosScreen(onPick: (ScenarioOption) -> Unit) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item {
            GroupedSection {
                ScenarioOption.all.forEach { option ->
                    GroupedRow(
                        onClick = { onPick(option) },
                        showDivider = option != ScenarioOption.all.last(),
                        leading = {
                            Icon(
                                option.icon.vector,
                                contentDescription = null,
                                tint = Gryonix.colors.accent,
                                modifier = Modifier.size(28.dp),
                            )
                        },
                        trailing = { DisclosureChevron() },
                    ) {
                        Column(
                            Modifier.weight(1f).padding(vertical = 4.dp),
                            verticalArrangement = Arrangement.spacedBy(3.dp),
                        ) {
                            Text(
                                stringResource(option.title),
                                style = MaterialTheme.typography.bodyLarge,
                                fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                                color = Gryonix.colors.label,
                            )
                            Text(
                                stringResource(option.subtitle),
                                style = MaterialTheme.typography.bodySmall,
                                color = Gryonix.colors.secondaryLabel,
                            )
                        }
                    }
                }
            }
        }
    }
}

val ScenarioIcon.vector: ImageVector
    get() = when (this) {
        ScenarioIcon.SERVER -> Icons.Outlined.Dns
        ScenarioIcon.RELAY -> Icons.Outlined.Hub
        ScenarioIcon.HOUSE -> Icons.Outlined.Home
        ScenarioIcon.CLOUD -> Icons.Outlined.Cloud
        ScenarioIcon.REFRESH -> Icons.Outlined.Autorenew
        ScenarioIcon.MESH -> Icons.Outlined.DeviceHub
    }
