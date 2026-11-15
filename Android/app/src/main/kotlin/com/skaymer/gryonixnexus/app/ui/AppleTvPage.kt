package com.skaymer.gryonixnexus.app.ui

import android.text.format.DateUtils
import androidx.compose.foundation.background
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Tv
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.tv.AppleTvLink
import com.skaymer.gryonixnexus.app.tv.TvNearby
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.FormSheet
import com.skaymer.gryonixnexus.app.ui.design.AlertFields
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.tvlink.TvPairedTv
import com.skaymer.gryonixnexus.tvlink.TvPairingAttempt
import com.skaymer.gryonixnexus.tvlink.TvPairingCode
import kotlinx.coroutines.launch

/** Settings › Apple TV: pair, confirm the license, send servers. */
@Composable
fun AppleTvPage(link: AppleTvLink, deployments: List<Deployment>) {
    val tvs by link.tvs.collectAsState()
    val nearby by link.nearby.collectAsState()
    val scope = rememberCoroutineScope()
    var pairing by remember { mutableStateOf<Pair<String, TvPairingAttempt>?>(null) }
    var sendingTo by remember { mutableStateOf<TvPairedTv?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }

    DisposableEffect(Unit) {
        link.startBrowsing()
        onDispose { link.stopBrowsing() }
    }
    LaunchedEffect(Unit) { link.vouchAll() }

    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item {
            PairedTvsSection(tvs, onSend = { sendingTo = it }, onForget = { scope.launch { link.forget(it) } },
                onConfirm = { scope.launch { link.confirmNow() } })
        }
        item {
            NearbyTvsSection(link.unpaired(nearby, tvs)) { tv ->
                scope.launch {
                    runCatching { link.beginPairing(tv.address) }
                        .onSuccess { pairing = tv.name to it }
                        .onFailure { failure = it.message }
                }
            }
        }
    }
    pairing?.let { (name, attempt) -> PairTvDialog(link, name, attempt) { pairing = null } }
    sendingTo?.let { tv -> SendServersDialog(link, tv, deployments) { sendingTo = null } }
    failure?.let { text ->
        IOSAlert(title = text, onDismiss = { failure = null },
            actions = listOf(AlertAction(stringResource(R.string.actions_ok), onSelect = { failure = null })))
    }
}

@Composable
private fun PairedTvsSection(
    tvs: List<TvPairedTv>,
    onSend: (TvPairedTv) -> Unit,
    onForget: (TvPairedTv) -> Unit,
    onConfirm: () -> Unit,
) {
    GroupedSection(header = stringResource(R.string.appletv_paired), footer = stringResource(R.string.appletv_paired_note)) {
        tvs.forEach { tv ->
            val confirmed = tv.vouchedAt?.let {
                stringResource(R.string.appletv_confirmed, DateUtils.getRelativeTimeSpanString(it * 1000).toString())
            }
            ValueRow(title = tv.name, value = null, onClick = null, subtitle = confirmed)
            ActionRow(stringResource(R.string.appletv_send), onClick = { onSend(tv) })
            ActionRow(stringResource(R.string.appletv_forget), onClick = { onForget(tv) }, danger = true)
        }
        if (tvs.isNotEmpty()) {
            ActionRow(stringResource(R.string.appletv_confirm_now), onClick = onConfirm, showDivider = false)
        }
    }
}

/** Gray, with a TV icon, while nothing is found */
@Composable
private fun LookingRow() {
    val colors = Gryonix.colors
    GroupedRow(
        showDivider = false,
        leading = { Icon(Icons.Outlined.Tv, null, modifier = Modifier.size(22.dp), tint = colors.secondaryLabel) },
    ) {
        Text(stringResource(R.string.appletv_looking), style = MaterialTheme.typography.bodyLarge,
            color = colors.secondaryLabel)
    }
}

@Composable
private fun NearbyTvsSection(nearby: List<TvNearby>, onPick: (TvNearby) -> Unit) {
    GroupedSection(header = stringResource(R.string.appletv_nearby), footer = stringResource(R.string.appletv_nearby_note)) {
        if (nearby.isEmpty()) {
            LookingRow()
        }
        nearby.forEachIndexed { index, tv ->
            ActionRow(tv.name, onClick = { onPick(tv) }, showDivider = index < nearby.lastIndex)
        }
    }
}

@Composable
private fun PairTvDialog(link: AppleTvLink, name: String, attempt: TvPairingAttempt, onDone: () -> Unit) {
    val scope = rememberCoroutineScope()
    var digits by remember { mutableStateOf("") }
    var wrong by remember { mutableStateOf(false) }
    val cancel = { attempt.cancel(); onDone() }
    FormSheet(
        title = stringResource(R.string.appletv_pair_title),
        message = if (wrong) stringResource(R.string.appletv_wrong_code) else stringResource(R.string.appletv_pair_prompt, name),
        onDismiss = cancel,
        actions = listOf(
            AlertAction(stringResource(R.string.actions_cancel), onSelect = cancel),
            AlertAction(stringResource(R.string.appletv_pair), preferred = true,
                enabled = TvPairingCode.parse(digits) != null && !wrong,
                onSelect = {
                    val code = TvPairingCode.parse(digits) ?: return@AlertAction
                    scope.launch {
                        runCatching { link.finishPairing(attempt, code) }
                            .onSuccess { onDone() }
                            .onFailure { wrong = true }
                    }
                }),
        ),
    ) {
        AlertFields {
            FieldRow(label = "123 456", value = digits, onValueChange = { digits = it },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword), showDivider = false)
        }
    }
}

@Composable
private fun SendServersDialog(link: AppleTvLink, tv: TvPairedTv, deployments: List<Deployment>, onDone: () -> Unit) {
    val scope = rememberCoroutineScope()
    var chosen by remember { mutableStateOf(emptySet<String>()) }
    var failure by remember { mutableStateOf<String?>(null) }
    FormSheet(
        title = tv.name,
        message = failure,
        onDismiss = onDone,
        actions = listOf(
            AlertAction(stringResource(R.string.actions_cancel), onSelect = onDone),
            AlertAction(stringResource(R.string.appletv_send_action), preferred = true, enabled = chosen.isNotEmpty(),
                onSelect = {
                    scope.launch {
                        runCatching { link.send(deployments.filter { it.id in chosen }, tv) }
                            .onSuccess { onDone() }
                            .onFailure { failure = it.message }
                    }
                }),
        ),
    ) {
        AlertFields {
            deployments.forEachIndexed { index, deployment ->
                CheckRow(deployment.name, checked = deployment.id in chosen,
                    onClick = { chosen = if (deployment.id in chosen) chosen - deployment.id else chosen + deployment.id },
                    showDivider = index < deployments.lastIndex)
            }
        }
    }
}
