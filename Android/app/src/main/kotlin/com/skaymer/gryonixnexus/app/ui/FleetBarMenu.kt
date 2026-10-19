package com.skaymer.gryonixnexus.app.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.IOSBarButton

class FleetBarCommands {
    enum class Command { ADD_SERVER, IMPORT, EXPORT_SEVERAL, REORDER }

    var pending by mutableStateOf<Command?>(null)
        private set

    var count by mutableIntStateOf(0)

    fun ask(command: Command) { pending = command }

    fun taken() { pending = null }
}

@Composable
fun FleetBarMenu(commands: FleetBarCommands, modifier: Modifier = Modifier) {
    var open by remember { mutableStateOf(false) }
    IOSBarButton(onClick = { open = true }, modifier = modifier) {
        Icon(
            Icons.Filled.MoreHoriz,
            contentDescription = stringResource(R.string.fleet_more),
            modifier = Modifier.size(26.dp),
        )
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.add_server)) },
            onClick = {
                open = false
                commands.ask(FleetBarCommands.Command.ADD_SERVER)
            },
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.import_server)) },
            onClick = {
                open = false
                commands.ask(FleetBarCommands.Command.IMPORT)
            },
        )
        if (commands.count > 0) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.export_several)) },
                onClick = {
                    open = false
                    commands.ask(FleetBarCommands.Command.EXPORT_SEVERAL)
                },
            )
        }
        if (commands.count > 1) {
            HorizontalDivider()
            DropdownMenuItem(
                text = { Text(stringResource(R.string.reorder_servers)) },
                onClick = {
                    open = false
                    commands.ask(FleetBarCommands.Command.REORDER)
                },
            )
        }
    }
}

class MetricsBarCommands {
    enum class Command { ADD_PANEL, ARRANGE }

    var pending by mutableStateOf<Command?>(null)
        private set

    /** Whether there is anything to add a panel ABOUT */
    var canAdd by mutableStateOf(false)

    var canArrange by mutableStateOf(false)

    fun ask(command: Command) { pending = command }

    fun taken() { pending = null }
}

/** The plus and the "…", in the shell's bar */
@Composable
fun MetricsBarActions(commands: MetricsBarCommands) {
    var open by remember { mutableStateOf(false) }
    IOSBarButton(
        onClick = { commands.ask(MetricsBarCommands.Command.ADD_PANEL) },
        enabled = commands.canAdd,
    ) {
        Icon(
            Icons.Filled.Add,
            contentDescription = stringResource(R.string.metrics_add_panel),
            modifier = Modifier.size(26.dp),
        )
    }
    IOSBarButton(onClick = { open = true }, enabled = commands.canArrange) {
        Icon(
            Icons.Filled.MoreHoriz,
            contentDescription = stringResource(R.string.metrics_board_options),
            modifier = Modifier.size(26.dp),
        )
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.metrics_arrange_panels)) },
            onClick = {
                open = false
                commands.ask(MetricsBarCommands.Command.ARRANGE)
            },
        )
    }
}
