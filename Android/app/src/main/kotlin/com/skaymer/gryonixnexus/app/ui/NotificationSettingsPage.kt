package com.skaymer.gryonixnexus.app.ui

import android.icu.text.MeasureFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import androidx.compose.ui.platform.LocalConfiguration
import com.skaymer.gryonixnexus.app.push.NotifySounds
import com.skaymer.gryonixnexus.app.push.NotifySoundGroup
import com.skaymer.gryonixnexus.app.push.NotifySound
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.DisposableEffect
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.notify.DevicePushProof
import com.skaymer.gryonixnexus.app.notify.NotifyChannelDefault
import gryonixnexusd.v1.SetNotifySettingsRequest
import com.skaymer.gryonixnexus.app.push.GryonixMessagingService
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.NotifyPreferences
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow

/** What every server tells this device about */
@Composable
fun NotificationSettingsPage(store: SettingsStore, secrets: SecretStore) {
    val revision by store.revision.collectAsState()
    val wishes = remember(revision) { NotifyPreferences.load(store) }
    val change: (NotifyPreferences) -> Unit = { it.save(store) }
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item { AppChannelSection(store) }
        item {
            GroupedSection(
                header = stringResource(R.string.notify_about),
                note = stringResource(R.string.notify_about_footer),
            ) {
                NotifyEventRows(wishes, change, withAppUpdate = true)
            }
        }
        item { NotifySoundsSection(store) }
        item { WidgetRefreshSection(wishes, change) }
        item { StopNotificationsSection(secrets) }
    }
}

/** The channel every server follows unless it keeps its own */
@Composable
private fun AppChannelSection(store: SettingsStore) {
    val app = androidx.compose.ui.platform.LocalContext.current.applicationContext as GryonixApplication
    val revision by store.revision.collectAsState()
    val choice = remember(revision) { NotifyChannelDefault.load(store) }
    var changed by remember { mutableStateOf(false) }
    DisposableEffect(Unit) {
        onDispose { if (changed) app.notify.syncAll(app.fleet.deployments.value) }
    }
    NotifyChannelSection(
        draft = choice.applied(SetNotifySettingsRequest()),
        header = stringResource(R.string.notify_where),
        note = stringResource(R.string.notify_where_hint),
    ) { request ->
        NotifyChannelDefault(request.channel, request.relay_url, request.ntfy_url, request.ntfy_topic).save(store)
        changed = true
    }
}

@Composable
private fun StopNotificationsSection(secrets: SecretStore) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val token = remember {
        context.getSharedPreferences(GryonixMessagingService.PREFERENCES, android.content.Context.MODE_PRIVATE)
            .getString(GryonixMessagingService.TOKEN_KEY, null)
    } ?: return
    val proof = remember { DevicePushProof(secrets) }
    var holding by remember { mutableStateOf<Int?>(null) }
    var stopped by remember { mutableStateOf<Int?>(null) }
    var confirming by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(token) { holding = withContext(Dispatchers.IO) { proof.serversHolding(token) } }
    GroupedSection(
        header = stringResource(R.string.notify_this_device),
        note = stringResource(R.string.notify_this_device_hint),
        footer = stopped?.let { stringResource(R.string.notify_stopped, it) },
    ) {
        holding?.let { ValueRow(stringResource(R.string.notify_servers_holding), it.toString(), onClick = null) }
        ActionRow(
            text = stringResource(R.string.notify_stop_all),
            danger = true,
            onClick = { confirming = true },
            showDivider = false,
        )
    }
    if (confirming) {
        ConfirmAlert(
            title = stringResource(R.string.notify_stop_all),
            confirm = stringResource(R.string.notify_stop_confirm),
            destructive = true,
            onConfirm = {
                confirming = false
                scope.launch {
                    stopped = withContext(Dispatchers.IO) { proof.stopAll(token) }
                    holding = withContext(Dispatchers.IO) { proof.serversHolding(token) }
                }
            },
            onCancel = { confirming = false },
        )
    }
}

/** A sound for each kind of alert */
@Composable
private fun NotifySoundsSection(store: SettingsStore) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val revision by store.revision.collectAsState()
    GroupedSection(header = stringResource(R.string.notify_sounds), note = stringResource(R.string.notify_sounds_note)) {
        NotifySoundGroup.entries.forEach { group ->
            val current = remember(revision) { NotifySounds.sound(store, group) }
            ChoiceRow(
                title = stringResource(group.title),
                value = stringResource(current.title),
                showDivider = group != NotifySoundGroup.entries.last(),
                options = NotifySound.entries.map { sound ->
                    stringResource(sound.title) to {
                        NotifySounds.set(store, group, sound)
                        sound.play(context)
                    }
                },
            )
        }
    }
}

/** How often servers refresh this device's widgets */
@Composable
private fun WidgetRefreshSection(wishes: NotifyPreferences, change: (NotifyPreferences) -> Unit) {
    val locale = LocalConfiguration.current.locales[0]
    GroupedSection(header = stringResource(R.string.widgets_section), note = stringResource(R.string.widgets_refresh_note)) {
        GroupedRow(showDivider = false) {
            IOSSegmentedControl(
                segments = NotifyPreferences.WIDGET_MINUTE_CHOICES,
                selected = wishes.widgetMinutes,
                label = { spelledMinutes(it, locale) },
                onSelect = { change(wishes.copy(widgetMinutes = it)) },
            )
        }
    }
}

/** A short span of minutes in the reader's language */
private fun spelledMinutes(minutes: Int, locale: java.util.Locale): String {
    val format = MeasureFormat.getInstance(locale, MeasureFormat.FormatWidth.SHORT)
    return if (minutes < 60) format.format(Measure(minutes, MeasureUnit.MINUTE)) else format.format(Measure(minutes / 60, MeasureUnit.HOUR))
}

/** The server events a person can switch on or off */
@Composable
fun NotifyEventRows(wishes: NotifyPreferences, change: (NotifyPreferences) -> Unit, withAppUpdate: Boolean) {
    ToggleRow(stringResource(R.string.notify_disks), wishes.disks, { change(wishes.copy(disks = it)) })
    if (wishes.disks) SpaceLimitRow(wishes, change)
    ToggleRow(stringResource(R.string.notify_services), wishes.services, { change(wishes.copy(services = it)) })
    ToggleRow(stringResource(R.string.notify_backups), wishes.backups, { change(wishes.copy(backups = it)) })
    ToggleRow(stringResource(R.string.notify_agent_update), wishes.agentUpdate, { change(wishes.copy(agentUpdate = it)) })
    if (withAppUpdate) {
        ToggleRow(stringResource(R.string.notify_app_update), wishes.appUpdate, { change(wishes.copy(appUpdate = it)) })
    }
    ToggleRow(stringResource(R.string.notify_operations), wishes.operations, { change(wishes.copy(operations = it)) })
    ToggleRow(
        stringResource(R.string.notify_ssh_logins), wishes.sshLogins,
        { change(wishes.copy(sshLogins = it)) },
    )
    ToggleRow(
        stringResource(R.string.notify_unusual_load), wishes.unusualLoad,
        { change(wishes.copy(unusualLoad = it)) }, showDivider = false,
    )
}

@Composable
private fun SpaceLimitRow(wishes: NotifyPreferences, change: (NotifyPreferences) -> Unit) {
    GroupedRow {
        IOSSegmentedControl(
            segments = listOf(80, 85, 90, 95),
            selected = wishes.spacePercent,
            label = { "$it%" },
            onSelect = { change(wishes.copy(spacePercent = it)) },
            modifier = Modifier.padding(vertical = 4.dp),
        )
    }
}
