package com.skaymer.gryonixnexus.app.ui

import android.text.format.DateUtils
import android.text.format.Formatter
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.agent.AgentHealthText
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import gryonixnexusd.v1.AgentHealth
import gryonixnexusd.v1.AgentModule

/** Memory, connections, uptime and add-ons of the agent itself */
@Composable
fun AgentHealthRows(health: AgentHealth) {
    val context = LocalContext.current
    fun size(bytes: Long) = Formatter.formatShortFileSize(context, AgentHealthText.nonNegative(bytes))
    ValueRow(
        title = stringResource(R.string.agent_health_memory),
        value = size(health.memory_bytes),
        subtitle = stringResource(R.string.agent_health_peak, size(health.peak_memory_bytes)),
        onClick = null,
    )
    ValueRow(
        title = stringResource(R.string.agent_health_connections),
        value = health.open_channels.toString(),
        onClick = null,
    )
    AgentHealthText.startedAt(health.started_at)?.let { started ->
        ValueRow(
            title = stringResource(R.string.agent_health_running_since),
            value = DateUtils.getRelativeTimeSpanString(
                started, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS,
            ).toString(),
            onClick = null,
        )
    }
    if (health.modules.isNotEmpty()) {
        Text(
            stringResource(R.string.agent_health_modules),
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        )
        health.modules.forEach { AgentModuleRow(it, ::size) }
    }
}

@Composable
private fun AgentModuleRow(module: AgentModule, size: (Long) -> String) {
    Row(
        Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            Modifier.size(8.dp).clip(CircleShape)
                .background(if (module.running) Color(0xFF34C759) else Color.Gray.copy(alpha = 0.5f)),
        )
        Text(module.name, Modifier.weight(1f))
        Text(
            AgentHealthText.moduleDetail(module.version, size(module.size_bytes)),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
