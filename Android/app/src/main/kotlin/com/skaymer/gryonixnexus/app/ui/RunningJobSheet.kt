package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.agent.RunningJob
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet

/** One run: its state, its log, its stop */
@Composable
fun RunningJobSheet(job: RunningJob, onStop: () -> Unit, onClose: () -> Unit) {
    IOSSheet(title = job.title, onClose = onClose, closeLabel = stringResource(R.string.close)) {
        GroupedSection {
            Text(
                jobState(job),
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                color = if (job.failure != null) MaterialTheme.colorScheme.error else Gryonix.colors.label,
            )
            RefusalAdvice(job.failure)
            if (!job.finished && job.host == null) {
                ActionRow(text = stringResource(R.string.notice_stop), onClick = onStop, showDivider = false)
            }
        }
        if (job.log.isNotEmpty()) JobLog(job.log)
    }
}

@Composable
private fun jobState(job: RunningJob): String = when {
    job.failure != null -> job.failure
    job.finished -> stringResource(R.string.notice_done)
    else -> stringResource(R.string.job_running_on_server)
}

@Composable
private fun JobLog(log: String) {
    GroupedSection(header = stringResource(R.string.service_logs)) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
            Text(
                log.trimEnd(),
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
                color = Gryonix.colors.secondaryLabel,
            )
        }
    }
}
