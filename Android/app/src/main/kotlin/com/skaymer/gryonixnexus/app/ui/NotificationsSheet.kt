package com.skaymer.gryonixnexus.app.ui

import android.Manifest
import android.net.Uri
import android.os.Build
import androidx.activity.compose.ManagedActivityResultLauncher
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.notify.NotifyPreferences
import com.skaymer.gryonixnexus.app.notify.NotifyScreenState
import com.skaymer.gryonixnexus.app.notify.NotifyTransfer
import com.skaymer.gryonixnexus.app.notify.NotifyViewModel
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.servercontrol.Deployment
import gryonixnexusd.v1.NotifyChannel
import gryonixnexusd.v1.NotifyDevice
import gryonixnexusd.v1.NotifySettings
import gryonixnexusd.v1.SetNotifySettingsRequest
import java.util.Locale

@Composable
fun NotificationsCard(onOpen: () -> Unit, showDivider: Boolean = true) {
    ValueRow(title = stringResource(R.string.notify_title), value = null, onClick = onOpen, showDivider = showDivider)
}

/** Where this server's health alerts go and what it checks */
@Composable
fun NotificationsDialog(deployment: Deployment, onClose: () -> Unit) {
    val model = (LocalContext.current.applicationContext as GryonixApplication).notify
    val screen by model.state.collectAsState()
    var draft by remember(deployment.id) { mutableStateOf<SetNotifySettingsRequest?>(null) }
    var followsApp by remember(deployment.id) { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(deployment.id) { model.load(deployment) }
    LaunchedEffect(screen.settings) {
        val settings = screen.settings ?: return@LaunchedEffect
        if (draft == null) draft = NotifyViewModel.draft(settings, Locale.getDefault().language)
        if (followsApp == null) followsApp = model.followsApp(deployment, settings)
    }
    val current = draft ?: NotifyViewModel.draft(null, Locale.getDefault().language)
    val context = LocalContext.current
    var transferNote by remember { mutableStateOf<Int?>(null) }
    val exportFile = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        runCatching {
            context.contentResolver.openOutputStream(uri)?.use { it.write(NotifyTransfer.of(current).encoded().toByteArray()) }
        }
    }
    val importFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri ?: return@rememberLauncherForActivityResult
        transferNote = try {
            val text = context.contentResolver.openInputStream(uri)?.use { it.readBytes().decodeToString() }.orEmpty()
            draft = NotifyTransfer.decode(text).applied(current)
            R.string.notify_import_loaded
        } catch (refused: NotifyTransfer.Refused) {
            if (refused.reason == NotifyTransfer.Failure.NEWER_VERSION) R.string.notify_import_newer
            else R.string.notify_import_invalid
        } catch (failure: Exception) {
            R.string.notify_import_invalid
        }
    }
    IOSSheet(
        title = stringResource(R.string.notify_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_cancel),
        action = SheetAction(
            title = stringResource(R.string.containers_save),
            enabled = !screen.isWorking && draft != null && NotifyViewModel.canSave(current),
            onSelect = { model.save(deployment, current, followsApp) },
        ),
    ) {
        val follows = followsApp ?: false
        NotifyChannelSection(current, follow = follows to { on ->
            followsApp = on
            if (on) draft = model.channelDefault.applied(current)
        }) { draft = it }
        NotifyEventsSection(current, { model.preferences }) { draft = it }
        NotifyStatusSection(screen.settings)
        NotifyDeviceSection(model, deployment, screen)
        NotifyDevicesList(screen.settings?.registered.orEmpty(), model.thisToken(), enabled = !screen.isWorking) {
            model.remove(deployment, it)
        }
        NotifyTransferSection(deployment, transferNote, exportFile, importFile)
    }
}

@Composable
private fun NotifyDevicesList(
    devices: List<NotifyDevice>,
    thisToken: String?,
    enabled: Boolean,
    onRemove: (String) -> Unit,
) {
    if (devices.isEmpty()) return
    GroupedSection(header = stringResource(R.string.license_devices), footer = stringResource(R.string.notify_devices_footer)) {
        devices.forEachIndexed { index, device ->
            val detail = if (device.token == thisToken) stringResource(R.string.devices_this_device) else device.app_version
            ValueRow(
                title = device.name.ifEmpty { if (device.platform == "fcm") "Android" else "Apple" },
                value = detail.ifEmpty { null },
                onClick = null,
                showDivider = true,
            )
            ActionRow(
                text = stringResource(R.string.vpn_remove),
                onClick = { onRemove(device.token) },
                enabled = enabled,
                danger = true,
                showDivider = index < devices.lastIndex,
            )
        }
    }
}

@Composable
private fun NotifyDeviceSection(model: NotifyViewModel, deployment: Deployment, screen: NotifyScreenState) {
    val onRelay = screen.settings?.channel == NotifyChannel.NOTIFY_CHANNEL_RELAY
    val askPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        model.registerThisDevice(deployment)
    }
    val footer = screen.message
        ?: if (screen.testSent) stringResource(R.string.notify_test_sent)
        else if (screen.deviceRegistered) stringResource(R.string.push_device_registered) else null
    GroupedSection(footer = footer) {
        if (onRelay) {
            ActionRow(
                text = stringResource(R.string.push_this_device),
                onClick = {
                    if (Build.VERSION.SDK_INT >= 33) {
                        askPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                    } else {
                        model.registerThisDevice(deployment)
                    }
                },
                enabled = !screen.isWorking,
                showDivider = true,
            )
        }
        ActionRow(
            text = stringResource(R.string.notify_test),
            onClick = { model.test(deployment) },
            enabled = !screen.isWorking && screen.settings?.channel.let {
                it == NotifyChannel.NOTIFY_CHANNEL_RELAY || it == NotifyChannel.NOTIFY_CHANNEL_NTFY
            },
            showDivider = false,
        )
    }
}

@Composable
private fun NotifyTransferSection(
    deployment: Deployment,
    note: Int?,
    exportFile: ManagedActivityResultLauncher<String, Uri?>,
    importFile: ManagedActivityResultLauncher<Array<String>, Uri?>,
) {
    GroupedSection(footer = note?.let { stringResource(it) } ?: stringResource(R.string.notify_transfer_footer)) {
        ActionRow(
            text = stringResource(R.string.notify_export),
            onClick = { exportFile.launch("gryonixPush-${deployment.name}.json") },
            showDivider = true,
        )
        ActionRow(
            text = stringResource(R.string.notify_import),
            onClick = { importFile.launch(arrayOf("application/json", "text/plain", "*/*")) },
            showDivider = false,
        )
    }
}

@Composable
internal fun NotifyChannelSection(
    draft: SetNotifySettingsRequest,
    header: String = stringResource(R.string.notify_channel),
    note: String? = null,
    follow: Pair<Boolean, (Boolean) -> Unit>? = null,
    onChange: (SetNotifySettingsRequest) -> Unit,
) {
    val channels = listOf(NotifyChannel.NOTIFY_CHANNEL_OFF, NotifyChannel.NOTIFY_CHANNEL_RELAY, NotifyChannel.NOTIFY_CHANNEL_NTFY)
    val footer = when (draft.channel) {
        NotifyChannel.NOTIFY_CHANNEL_RELAY -> stringResource(R.string.notify_relay_android)
        NotifyChannel.NOTIFY_CHANNEL_NTFY -> stringResource(R.string.notify_ntfy_rule)
        else -> stringResource(R.string.notify_explains)
    }
    val locked = follow?.first == true
    GroupedSection(header = header, note = note, footer = footer) {
        follow?.let { (on, set) -> ToggleRow(stringResource(R.string.notify_use_app_channel), on, set) }
        if (!locked) NotifyChannelRows(draft, channels, onChange)
    }
}

@Composable
private fun NotifyChannelRows(
    draft: SetNotifySettingsRequest,
    channels: List<NotifyChannel>,
    onChange: (SetNotifySettingsRequest) -> Unit,
) {
    GroupedRow(showDivider = draft.channel != NotifyChannel.NOTIFY_CHANNEL_OFF) {
        IOSSegmentedControl(
            segments = channels,
            selected = draft.channel,
            label = { channelName(it) },
            onSelect = { onChange(draft.copy(channel = it)) },
            modifier = Modifier.padding(vertical = 4.dp),
        )
    }
    when (draft.channel) {
        NotifyChannel.NOTIFY_CHANNEL_RELAY -> FieldRow(
            label = stringResource(R.string.notify_relay_address), value = draft.relay_url,
            onValueChange = { onChange(draft.copy(relay_url = it.trim())) },
            placeholder = "https://push.example.com", showDivider = false,
        )
        NotifyChannel.NOTIFY_CHANNEL_NTFY -> {
            FieldRow(
                label = stringResource(R.string.notify_ntfy_server), value = draft.ntfy_url,
                onValueChange = { onChange(draft.copy(ntfy_url = it.trim())) },
            )
            FieldRow(
                label = stringResource(R.string.notify_topic), value = draft.ntfy_topic,
                onValueChange = { onChange(draft.copy(ntfy_topic = it.trim())) }, showDivider = false,
            )
        }
        else -> {}
    }
}

/** The app defaults, or this server's own events */
@Composable
private fun NotifyEventsSection(
    draft: SetNotifySettingsRequest,
    defaults: () -> NotifyPreferences,
    onChange: (SetNotifySettingsRequest) -> Unit,
) {
    GroupedSection(header = stringResource(R.string.notify_about), note = stringResource(R.string.notify_use_defaults_footer)) {
        ToggleRow(
            stringResource(R.string.notify_use_defaults), !draft.custom_checks,
            { follow ->
                onChange(if (follow) draft.copy(custom_checks = false, checks = defaults().checks) else draft.copy(custom_checks = true))
            },
            showDivider = draft.custom_checks,
        )
        if (draft.custom_checks) {
            NotifyEventRows(
                NotifyPreferences.from(draft.checks ?: defaults().checks),
                { onChange(draft.copy(checks = it.checks)) },
                withAppUpdate = false,
            )
        }
    }
}

@Composable
private fun channelName(channel: NotifyChannel): String = when (channel) {
    NotifyChannel.NOTIFY_CHANNEL_RELAY -> "gryonixPush"
    NotifyChannel.NOTIFY_CHANNEL_NTFY -> "ntfy"
    else -> stringResource(R.string.notify_nothing)
}

@Composable
private fun NotifyStatusSection(settings: NotifySettings?) {
    settings ?: return
    val lines = settings.active_problems + listOfNotNull(
        settings.relay_maintenance.ifEmpty { null }?.let { stringResource(R.string.notify_relay_maintenance, it) },
        settings.last_error.ifEmpty { null },
    )
    if (lines.isEmpty()) return
    GroupedSection(header = stringResource(R.string.notify_status)) {
        lines.forEachIndexed { index, line ->
            GroupedRow(showDivider = index != lines.lastIndex) {
                Text(line, style = MaterialTheme.typography.bodyMedium, color = Gryonix.colors.secondaryLabel)
            }
        }
    }
}
