package com.skaymer.gryonixnexus.app.widgets

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.lifecycle.lifecycleScope
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.GroupedBackground
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GryonixTheme
import com.skaymer.gryonixnexus.app.ui.design.SystemBarsFollowTheme
import kotlinx.coroutines.launch

/** Picks which server a placed widget shows */
class WidgetServerPickerActivity : ComponentActivity() {
    private var widget = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        widget = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, widget) ?: widget
        setResult(RESULT_CANCELED, answer())
        if (widget == AppWidgetManager.INVALID_APPWIDGET_ID) return finish()
        val servers = WidgetServerChoice.choices(FleetSnapshotStore(this).read())
        val chosen = WidgetServerChoice(this).server(widget)
        enableEdgeToEdge()
        setContent {
            SystemBarsFollowTheme(this)
            GryonixTheme {
                Picker(servers, chosen) { choose(it) }
            }
        }
    }

    private fun choose(server: String?) {
        WidgetServerChoice(this).choose(widget, server)
        lifecycleScope.launch {
            runCatching {
                val id = GlanceAppWidgetManager(this@WidgetServerPickerActivity).getGlanceIdBy(widget)
                SnapshotWidget.forWidget(this@WidgetServerPickerActivity, widget)?.update(this@WidgetServerPickerActivity, id)
            }
            setResult(RESULT_OK, answer())
            finish()
        }
    }

    private fun answer() = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widget)
}

@Composable
private fun Picker(servers: List<FleetSnapshot.Server>, chosen: String?, onChoose: (String?) -> Unit) {
    GroupedBackground(Modifier.fillMaxSize()) {
        Column(Modifier.safeDrawingPadding().verticalScroll(rememberScrollState()).padding(vertical = 16.dp)) {
            Text(
                stringResource(R.string.widget_server_title),
                style = MaterialTheme.typography.headlineMedium,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
            )
            GroupedSection(footer = stringResource(R.string.widget_server_footer)) {
                ChoiceRow(stringResource(R.string.widget_server_first), chosen == null, servers.isEmpty()) { onChoose(null) }
                servers.forEachIndexed { index, server ->
                    ChoiceRow(server.name, server.id == chosen, index == servers.lastIndex) { onChoose(server.id) }
                }
            }
        }
    }
}

@Composable
private fun ChoiceRow(title: String, checked: Boolean, last: Boolean, onClick: () -> Unit) {
    GroupedRow(
        onClick = onClick,
        showDivider = !last,
        trailing = {
            if (checked) Icon(Icons.Filled.Check, contentDescription = null, tint = Gryonix.colors.accent)
        },
    ) {
        Text(title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
    }
}
