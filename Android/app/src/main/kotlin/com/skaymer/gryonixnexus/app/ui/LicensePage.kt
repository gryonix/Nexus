package com.skaymer.gryonixnexus.app.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.licensing.ActivationCode
import com.skaymer.gryonixnexus.app.licensing.LicenseDeviceList
import com.skaymer.gryonixnexus.app.licensing.LicenseFailure
import com.skaymer.gryonixnexus.app.licensing.LicensePlan
import com.skaymer.gryonixnexus.app.licensing.LicenseStatus
import com.skaymer.gryonixnexus.app.licensing.LicenseStore
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.launch

private const val BUY_URL = "https://gryonix.com/buy"

/** The license page of Settings */
@Composable
fun LicensePage(store: SettingsStore, fleet: FleetRepository) {
    Column(
        Modifier
            .fillMaxSize()
            .background(Gryonix.colors.groupedBackground)
            .verticalScroll(rememberScrollState())
            .padding(GroupedContentPadding),
        verticalArrangement = GroupedSpacing,
    ) {
        LicenseSections(store, fleet, locked = false)
    }
}

/** Status, buying, code, devices and demo */
@Composable
fun ColumnScope.LicenseSections(store: SettingsStore, fleet: FleetRepository, locked: Boolean) {
    val license = licenseStore()
    val status by license.status.collectAsState()
    val code by license.code.collectAsState()
    LaunchedEffect(Unit) { license.refreshIfDue() }
    LicenseStatusSection(status, locked)
    if ((status as? LicenseStatus.Active)?.plan != LicensePlan.LIFETIME) LicenseBuySection()
    LicenseCodeSection(license, code, status is LicenseStatus.Active)
    code?.let { LicenseDevicesSection(license, it) }
    LicenseDemoSection(store, fleet)
}

@Composable
internal fun licenseStore(): LicenseStore =
    (LocalContext.current.applicationContext as GryonixApplication).license

@Composable
private fun LicenseStatusSection(status: LicenseStatus, locked: Boolean) {
    GroupedSection(footer = stringResource(R.string.license_status_footer)) {
        if (locked) {
            GroupedRow { RowLabel(stringResource(licenseLockMessage())) }
        }
        ValueRow(
            title = stringResource(R.string.license_status),
            value = licenseStatusText(status),
            onClick = null,
            showDivider = false,
        )
    }
}

@Composable
internal fun licenseStatusText(status: LicenseStatus): String = when (status) {
    LicenseStatus.Demo -> stringResource(R.string.license_demo)
    LicenseStatus.Expired -> stringResource(R.string.license_ended)
    is LicenseStatus.Active -> status.expires?.let { end ->
        val date = DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(end * 1000))
        stringResource(R.string.license_until, planName(status.plan), date)
    } ?: planName(status.plan)
}

@Composable
private fun planName(plan: LicensePlan): String = stringResource(
    when (plan) {
        LicensePlan.MONTHLY -> R.string.license_monthly
        LicensePlan.YEARLY -> R.string.license_yearly
        LicensePlan.LIFETIME -> R.string.license_forever
    }
)

@Composable
private fun LicenseBuySection() {
    val context = LocalContext.current
    GroupedSection(header = stringResource(R.string.license_buy)) {
        ActionRow(
            text = stringResource(R.string.license_buy_site),
            showDivider = false,
            onClick = {
                context.startActivity(
                    Intent(Intent.ACTION_VIEW, Uri.parse(BUY_URL)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            },
        )
    }
}

@Composable
private fun LicenseCodeSection(license: LicenseStore, code: String?, active: Boolean) {
    GroupedSection(
        header = stringResource(R.string.license_code),
        note = stringResource(R.string.license_code_footer),
    ) {
        if (code != null && active) CodeInUseRows(license, code) else CodeEntryRows(license)
    }
}

@Composable
private fun CodeInUseRows(license: LicenseStore, code: String) {
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    GroupedRow(
        trailing = {
            TextButton(onClick = { clipboard.setText(AnnotatedString(code)) }) {
                Text(stringResource(R.string.license_copy), color = Gryonix.colors.accent)
            }
        },
    ) {
        RowLabel(code)
    }
    ActionRow(
        text = stringResource(R.string.license_remove_here),
        danger = true,
        showDivider = false,
        onClick = { scope.launch { license.removeFromThisDevice() } },
    )
}

@Composable
private fun CodeEntryRows(license: LicenseStore) {
    var input by remember { mutableStateOf("") }
    var working by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<LicenseFailure?>(null) }
    val scope = rememberCoroutineScope()
    FieldRow(
        label = stringResource(R.string.license_code),
        value = input,
        onValueChange = { input = it },
        placeholder = "XXXXX-XXXXX-XXXXX-XXXXX",
    )
    ActionRow(
        text = stringResource(R.string.license_activate),
        enabled = !working && ActivationCode.normalize(input) != null,
        showDivider = failure != null,
        onClick = {
            working = true
            scope.launch {
                failure = license.activate(input)
                if (failure == null) input = ""
                working = false
            }
        },
    )
    failure?.let { GroupedRow(showDivider = false) { RowLabel(stringResource(failureText(it))) } }
}

internal fun failureText(failure: LicenseFailure): Int = when (failure) {
    LicenseFailure.UNKNOWN_CODE -> R.string.license_unknown_code
    LicenseFailure.EXPIRED -> R.string.license_expired
    LicenseFailure.REVOKED -> R.string.license_revoked
    LicenseFailure.DEVICE_LIMIT -> R.string.license_device_limit
    LicenseFailure.WRONG_PRODUCT -> R.string.license_wrong_product
    LicenseFailure.OFFLINE -> R.string.license_offline
    LicenseFailure.REJECTED -> R.string.license_rejected
}

@Composable
private fun LicenseDevicesSection(license: LicenseStore, code: String) {
    var list by remember(code) { mutableStateOf<LicenseDeviceList?>(null) }
    var reload by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(code, reload) { list = license.devices() }
    val shown = list ?: return
    GroupedSection(
        header = stringResource(R.string.license_devices),
        footer = stringResource(R.string.license_devices_count, shown.devices.size, shown.limit),
    ) {
        shown.devices.forEachIndexed { index, device ->
            LicenseDeviceRow(
                name = device.name ?: device.platform ?: "—",
                isThis = device.device == license.thisDevice(),
                showDivider = index != shown.devices.lastIndex,
                onRemove = { scope.launch { license.removeDevice(device.device); reload++ } },
            )
        }
    }
}

@Composable
private fun LicenseDeviceRow(name: String, isThis: Boolean, showDivider: Boolean, onRemove: () -> Unit) {
    GroupedRow(
        showDivider = showDivider,
        trailing = {
            if (!isThis) {
                IconButton(onClick = onRemove) {
                    Icon(
                        Icons.Filled.RemoveCircleOutline,
                        contentDescription = stringResource(R.string.license_remove),
                        tint = Gryonix.colors.danger,
                    )
                }
            }
        },
    ) {
        RowLabel(name, if (isThis) stringResource(R.string.license_this_device) else null)
    }
}

@Composable
private fun LicenseDemoSection(store: SettingsStore, fleet: FleetRepository) {
    val revision by store.revision.collectAsState()
    GroupedSection(footer = stringResource(R.string.license_forever_terms)) {
        DemoFleetRow(store, fleet, revision)
    }
}
