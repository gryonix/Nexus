package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.agentcontrol.ServiceMoveProblem
import com.skaymer.gryonixnexus.app.servers.MoveRun
import com.skaymer.gryonixnexus.app.servers.ServiceMoveViewModel
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ServiceMoveRefusal
import com.skaymer.gryonixnexus.servercontrol.ServiceMoveStep

private fun stepText(step: ServiceMoveStep): Int = when (step) {
    ServiceMoveStep.CHECK -> R.string.move_step_check
    ServiceMoveStep.INSTALL -> R.string.move_step_install
    ServiceMoveStep.BACKUP -> R.string.move_step_backup
    ServiceMoveStep.STOP -> R.string.move_step_stop
    ServiceMoveStep.SEND -> R.string.move_step_send
    ServiceMoveStep.RESTORE -> R.string.move_step_restore
    ServiceMoveStep.SWITCH_ENTRY -> R.string.move_step_switch
    ServiceMoveStep.VERIFY -> R.string.move_step_verify
    ServiceMoveStep.FINISH -> R.string.move_step_finish
}

@Composable
private fun refusalText(reason: ServiceMoveRefusal, name: String): String = when (reason) {
    ServiceMoveRefusal.NOT_MOVABLE -> stringResource(R.string.move_refuse_not_movable, name)
    ServiceMoveRefusal.NO_AGENT -> stringResource(R.string.move_refuse_no_agent)
    ServiceMoveRefusal.SAME_MACHINE, ServiceMoveRefusal.UNKNOWN_MACHINE ->
        stringResource(R.string.move_refuse_unknown_machine)
    ServiceMoveRefusal.TARGET_DOES_NOT_RUN_SERVICES -> stringResource(R.string.move_refuse_not_a_worker)
    ServiceMoveRefusal.NO_FRONT -> stringResource(R.string.move_refuse_no_front)
}

@Composable
private fun reasonText(error: Throwable, name: String): String = when (error) {
    is ServiceMoveProblem.NotOnSource -> stringResource(R.string.move_problem_not_on_source, name)
    is ServiceMoveProblem.AlreadyOnTarget -> stringResource(R.string.move_problem_already_on_target, name)
    is ServiceMoveProblem.NoSiteOnFront -> stringResource(R.string.move_problem_no_site, name)
    is ServiceMoveProblem.FrontDisagrees -> stringResource(R.string.move_problem_front_disagrees, name)
    is ServiceMoveProblem.NotAnswering -> stringResource(R.string.move_problem_not_answering, error.status)
    is ServiceMoveProblem.NoArchive -> stringResource(R.string.move_problem_no_archive)
    is ServiceMoveProblem.NoLoginAccess -> stringResource(R.string.move_problem_no_login)
    else -> error.message ?: error.toString()
}

@Composable
private fun failureText(run: MoveRun): String {
    val failure = run.failure
    val lines = mutableListOf<String>()
    lines += stringResource(R.string.move_not_finished)
    val cause = failure?.underlying ?: run.error
    if (cause != null) lines += reasonText(cause, run.serviceName)
    val undone = failure?.undone ?: run.undone
    if (failure != null && failure.step <= ServiceMoveStep.BACKUP) {
        lines += stringResource(R.string.move_undo_nothing_changed)
    } else if (undone?.sourceStarted == true) {
        lines += stringResource(R.string.move_undo_source_running)
    }
    if (undone?.entryRestored == true) lines += stringResource(R.string.move_undo_entry_back)
    if (undone?.targetCopyRemoved == true) lines += stringResource(R.string.move_undo_copy_removed)
    if (undone != null && undone.problems.isNotEmpty()) {
        lines += stringResource(R.string.move_undo_problems, undone.problems.joinToString("; "))
    }
    return lines.joinToString("\n")
}

@Composable
fun ServiceMoveDialogs(moves: ServiceMoveViewModel) {
    val ask by moves.ask.collectAsState()
    val refused by moves.refused.collectAsState()
    val run by moves.run.collectAsState()

    ask?.let { pending ->
        val target = pending.route.target.name.ifEmpty { pending.route.target.endpoint.host }
        IOSAlert(
            title = stringResource(R.string.move_confirm_title, pending.serviceName, target),
            message = stringResource(R.string.move_confirm_message),
            onDismiss = moves::cancelAsk,
            actions = listOf(
                AlertAction(stringResource(R.string.containers_cancel), onSelect = moves::cancelAsk),
                AlertAction(stringResource(R.string.move_confirm_action), preferred = true, onSelect = moves::confirm),
            ),
        )
    }
    refused?.let { refusal ->
        IOSAlert(
            title = stringResource(R.string.move_cannot_title),
            message = refusalText(refusal.reason, refusal.serviceName),
            onDismiss = moves::clearRefusal,
            actions = listOf(AlertAction(stringResource(R.string.containers_done), preferred = true, onSelect = moves::clearRefusal)),
        )
    }
    run?.let { MoveRunDialog(it, moves) }
}

@Composable
private fun MoveRunDialog(run: MoveRun, moves: ServiceMoveViewModel) {
    IOSAlert(
        title = stringResource(R.string.move_title, run.serviceName, run.targetName),
        onDismiss = { if (run.isFinished) moves.clearRun() },
        actions = listOf(
            AlertAction(
                stringResource(R.string.containers_done),
                preferred = true,
                enabled = run.isFinished,
                onSelect = moves::clearRun,
            ),
        ),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            MoveRunStatus(run)
            if (run.log.isNotEmpty()) {
                Text(
                    run.log,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = Gryonix.colors.secondaryLabel,
                    modifier = Modifier.heightIn(max = 240.dp).verticalScroll(rememberScrollState()),
                )
            }
        }
    }
}

@Composable
private fun MoveRunStatus(run: MoveRun) {
    val failed = run.failure != null || run.error != null || run.undone?.problems.orEmpty().isNotEmpty()
    when {
        failed -> Text(
            if (run.putBack && run.failure == null && run.error == null) {
                stringResource(R.string.move_undo_problems, run.undone?.problems.orEmpty().joinToString("; "))
            } else {
                failureText(run)
            },
            style = MaterialTheme.typography.bodyMedium,
            color = Gryonix.colors.danger,
            textAlign = TextAlign.Center,
        )
        run.isFinished -> Text(
            if (run.putBack) {
                stringResource(R.string.move_all_back)
            } else {
                stringResource(R.string.move_done, run.serviceName, run.targetName)
            },
            style = MaterialTheme.typography.bodyMedium,
            color = Gryonix.colors.label,
            textAlign = TextAlign.Center,
        )
        else -> Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Gryonix.colors.tertiaryLabel)
            Text(
                stringResource(if (run.undoing) R.string.move_putting_back else stepText(run.step)),
                style = MaterialTheme.typography.bodyMedium,
                color = Gryonix.colors.secondaryLabel,
            )
        }
    }
}

@Composable
fun InterruptedMoveCard(deployment: Deployment, moves: ServiceMoveViewModel, name: String, target: String) {
    GroupedSection(
        header = stringResource(R.string.move_interrupted_title),
        footer = stringResource(R.string.move_interrupted_message, name, target),
    ) {
        ActionRow(
            text = stringResource(R.string.move_continue),
            onClick = { moves.resume(deployment, putBack = false) },
        )
        ActionRow(
            text = stringResource(R.string.move_put_back),
            onClick = { moves.resume(deployment, putBack = true) },
            showDivider = false,
        )
    }
}
