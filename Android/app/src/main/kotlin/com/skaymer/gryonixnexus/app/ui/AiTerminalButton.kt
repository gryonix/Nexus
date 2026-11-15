package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.aiassistant.AIContextKind
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.ai.AiExplain
import com.skaymer.gryonixnexus.app.shell.AppModule
import com.skaymer.gryonixnexus.app.terminal.TerminalViewModel
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet

/** "Ask AI" in the terminal; answers can only be copied. */
@Composable
fun AiTerminalButton(terminal: TerminalViewModel, modifier: Modifier = Modifier) {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val on by app.modules.on.collectAsState()
    if (AppModule.AI !in on) return
    var menu by remember { mutableStateOf(false) }
    var describing by remember { mutableStateOf(false) }
    val title = stringResource(R.string.tab_terminal)
    Column(modifier) {
        TextButton(onClick = { menu = true }) { Text(stringResource(R.string.ai_ask_ai)) }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.ai_explain_command)) }, onClick = {
                menu = false
                app.aiChats.start(AiExplain.terminal(AIContextKind.TERMINAL_EXPLAIN, "", "Terminal", screenTail(terminal), title))
            })
            DropdownMenuItem(text = { Text(stringResource(R.string.ai_describe_need)) }, onClick = { menu = false; describing = true })
        }
    }
    if (describing) DescribeSheet(title, onClose = { describing = false }) { need ->
        describing = false
        app.aiChats.start(AiExplain.terminal(AIContextKind.TERMINAL_ASK, "", "Need", need, title))
    }
}

@Composable
private fun DescribeSheet(title: String, onClose: () -> Unit, onAsk: (String) -> Unit) {
    var need by remember { mutableStateOf("") }
    IOSSheet(title = stringResource(R.string.ai_describe_need), onClose = onClose, closeLabel = stringResource(R.string.ai_cancel)) {
        OutlinedTextField(need, { need = it }, Modifier.padding(16.dp), placeholder = { Text(stringResource(R.string.ai_what_do)) })
        Text(stringResource(R.string.ai_copy_only), Modifier.padding(horizontal = 16.dp))
        TextButton(onClick = { onAsk(need.trim()) }, enabled = need.isNotBlank()) { Text(stringResource(R.string.ai_ask)) }
    }
}

private fun screenTail(terminal: TerminalViewModel): String =
    terminal.emulator.screen.map { row -> row.joinToString("") { it.char.toString() }.trimEnd() }
        .filter { it.isNotEmpty() }.takeLast(30).joinToString("\n")
