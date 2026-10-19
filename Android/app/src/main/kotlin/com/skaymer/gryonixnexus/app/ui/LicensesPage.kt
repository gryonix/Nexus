package com.skaymer.gryonixnexus.app.ui

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.app.ui.design.Gryonix

/** Every third-party license this build carries */
@Composable
fun LicensesPage() {
    val context = LocalContext.current
    val blocks = remember { ThirdPartyNotices.blocks(context) }
    SelectionContainer {
        LazyColumn(Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground)) {
            items(blocks) { block ->
                Text(
                    block,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                )
            }
        }
    }
}

/** The generated notices file, cut into one block per component */
object ThirdPartyNotices {
    const val ASSET = "third_party_notices.txt"
    private const val RULE = "========================================================================"

    fun blocks(context: Context): List<String> =
        split(context.assets.open(ASSET).bufferedReader().use { it.readText() })

    /** A heading is a name line between two rules */
    fun split(text: String): List<String> {
        val lines = text.lines()
        val blocks = mutableListOf<MutableList<String>>(mutableListOf())
        var i = 0
        while (i < lines.size) {
            if (lines[i] == RULE && lines.getOrNull(i + 2) == RULE) {
                blocks += mutableListOf(lines[i + 1], "")
                i += 3
            } else {
                blocks.last() += lines[i]
                i += 1
            }
        }
        return blocks.map { it.joinToString("\n").trim() }.filter { it.isNotEmpty() }
    }
}
