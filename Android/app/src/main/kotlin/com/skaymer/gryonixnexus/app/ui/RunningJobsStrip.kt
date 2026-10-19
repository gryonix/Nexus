package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.WrapperLogText
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ErrorOutline
import com.skaymer.gryonixnexus.app.agent.RunningJob
import com.skaymer.gryonixnexus.app.agent.RunningJobs

@Composable
fun RunningJobsStrip(jobs: RunningJobs) {
    val running by jobs.jobs.collectAsState()
    if (running.isEmpty()) return
    Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant)) {
        running.forEach { job ->
            RunningJobRow(job) { jobs.dismiss(job.key) }
        }
    }
}

@Composable
private fun RunningJobRow(job: RunningJob, onDismiss: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(enabled = job.finished) { onDismiss() }
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        when {
            !job.finished -> CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
            job.failure != null -> Icon(
                Icons.Filled.ErrorOutline,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(18.dp),
            )
            else -> Icon(
                Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(18.dp),
            )
        }
        Column(Modifier.padding(start = 12.dp)) {
            Text(job.title, style = MaterialTheme.typography.bodyMedium)
            val detail = job.failure ?: stageText(job)
            if (detail.isNotEmpty()) {
                Text(
                    detail,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun stageText(job: RunningJob): String = when {
    job.stage == WrapperLogText.Stage.BACKUP -> stringResource(R.string.job_stage_backup)
    job.stage == WrapperLogText.Stage.WAITING -> stringResource(R.string.job_stage_waiting)
    job.line.isNotEmpty() && !job.finished -> stringResource(R.string.job_running_on_server)
    else -> ""
}
