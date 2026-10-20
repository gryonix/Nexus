package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.app.shell.AppTourRequests
import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.ui.graphics.Color
import androidx.compose.material3.MaterialTheme
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.ui.text.input.PasswordVisualTransformation
import com.skaymer.gryonixnexus.app.secrets.CloudflareTokenStore
import androidx.compose.runtime.Composable
import android.content.Intent
import android.provider.Settings
import android.net.Uri
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.app.updates.AppUpdate
import com.skaymer.gryonixnexus.app.updates.AppUpdateViewModel
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Edit
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.activity.compose.BackHandler
import androidx.compose.material.icons.filled.ArrowDownward
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.configurator.DNSProviderKind
import com.skaymer.gryonixnexus.app.secrets.DNSCredential
import com.skaymer.gryonixnexus.app.secrets.DNSCredentialTokenStore
import com.skaymer.gryonixnexus.app.secrets.DNSCredentials
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.security.GatedAction
import com.skaymer.gryonixnexus.app.security.LocalDeviceGate
import kotlinx.coroutines.launch
import com.skaymer.gryonixnexus.app.security.SecuritySettings
import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import com.skaymer.gryonixnexus.app.licensing.LicensePrompt
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.app.metrics.ChartScale
import com.skaymer.gryonixnexus.app.metrics.HistoryPresentation
import com.skaymer.gryonixnexus.app.metrics.HistoryMetric
import com.skaymer.gryonixnexus.app.metrics.HistoryRange
import com.skaymer.gryonixnexus.app.metrics.MetricsPreferences
import com.skaymer.gryonixnexus.app.metrics.OfferedCharts
import com.skaymer.gryonixnexus.app.servers.MetricsDisplaySettings
import com.skaymer.gryonixnexus.app.servers.WakeButtonSettings
import com.skaymer.gryonixnexus.app.servers.ConnectionSettings
import com.skaymer.gryonixnexus.app.servers.ServerCardColumns
import com.skaymer.gryonixnexus.app.shell.AppAccent
import com.skaymer.gryonixnexus.app.shell.AppTab
import com.skaymer.gryonixnexus.app.shell.hapticsEnabled
import com.skaymer.gryonixnexus.app.shell.setHapticsEnabled
import com.skaymer.gryonixnexus.app.shell.appAccent
import com.skaymer.gryonixnexus.app.shell.setAppAccent
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.app.shell.ShellSectionVisibility
import com.skaymer.gryonixnexus.app.shell.TabBarSettings
import com.skaymer.gryonixnexus.app.ui.design.colour
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSwitch
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.servercontrol.MetricsIndicatorStyle
import com.skaymer.gryonixnexus.servercontrol.ServerCardSize

@Composable
fun SettingsSection(
    tabs: TabBarSettings,
    store: SettingsStore,
    fleet: FleetRepository,
    /** The Cloudflare tokens — what the tunnel paths read */
    cloudflare: CloudflareTokenStore,
    credentials: DNSCredentials,
    /** Where those tokens live — see `DNSCredentialTokenStore` */
    secrets: SecretStore,
    /** Whether a newer APK exists — see `AppUpdate` */
    appUpdates: AppUpdateViewModel,
    pushed: PushedScreen? = null,
) {
    var page by rememberSaveable { mutableStateOf<String?>(null) }

    if (page != null) {
        val title = stringResource(
            when (page) {
                PAGE_APPEARANCE -> R.string.settings_appearance
                PAGE_APPEARANCE_APP -> R.string.settings_appearance_app
                PAGE_APPEARANCE_CARDS -> R.string.settings_cards
                PAGE_APPEARANCE_CHARTS -> R.string.settings_appearance_charts
                PAGE_APPEARANCE_SERVER -> R.string.settings_server_screen
                PAGE_SECTIONS -> R.string.settings_sections
                PAGE_SECURITY -> R.string.settings_security
                PAGE_NOTIFICATIONS -> R.string.notify_push_title
                PAGE_OPERATIONS -> R.string.operations_page_title
                PAGE_RANGES -> R.string.settings_offered_ranges
                PAGE_METRICS -> R.string.settings_offered_metrics
                PAGE_LICENSES -> R.string.settings_licenses
                PAGE_LICENSE -> R.string.license_title
                else -> R.string.cloudflare_title
            }
        )
        BackHandler { page = null }
        DisposableEffect(title) {
            pushed?.push(title) { page = null }
            onDispose { pushed?.clear() }
        }
        when (page) {
            PAGE_APPEARANCE -> AppearancePage(store, tabs) { page = it }
            PAGE_APPEARANCE_APP -> AppearanceAppPage(store)
            PAGE_APPEARANCE_CARDS -> AppearanceCardsPage(store)
            PAGE_APPEARANCE_CHARTS -> AppearanceChartsPage(store) { page = it }
            PAGE_APPEARANCE_SERVER -> AppearanceServerScreenPage(tabs)
            PAGE_RANGES -> OfferedRangesPage(store)
            PAGE_METRICS -> OfferedMetricsPage(store)
            PAGE_SECTIONS -> SectionsPage(tabs, store)
            PAGE_SECURITY -> SecurityPage(store)
            PAGE_NOTIFICATIONS -> NotificationSettingsPage(store, secrets)
            PAGE_OPERATIONS -> OperationNoticeSettingsPage(store)
            PAGE_LICENSES -> LicensesPage()
            PAGE_LICENSE -> LicensePage(store, fleet)
            else -> LicenseLocked { DNSAPIPage(credentials, DNSCredentialTokenStore(secrets), store) }
        }
        return
    }

    val revision by store.revision.collectAsState()

    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item { LicenseSettingsRow { page = PAGE_LICENSE } }
        item {
            GroupedSection {
                PageRow(stringResource(R.string.settings_appearance)) { page = PAGE_APPEARANCE }
                PageRow(stringResource(R.string.settings_sections)) { page = PAGE_SECTIONS }
                PageRow(stringResource(R.string.settings_security)) { page = PAGE_SECURITY }
                PageRow(stringResource(R.string.notify_push_title)) { page = PAGE_NOTIFICATIONS }
                PageRow(stringResource(R.string.operations_page_title), showDivider = false) {
                    page = PAGE_OPERATIONS
                }
            }
        }
        item {
            var showingProxies by remember { mutableStateOf(false) }
            GroupedSection {
                PageRow(stringResource(R.string.proxies), showDivider = false) {
                    if (LicensePrompt.allow()) showingProxies = true
                }
            }
            if (showingProxies) {
                ProxyListSheet(store, secrets) { showingProxies = false }
            }
        }
        item {
            GroupedSection {
                val chosen = remember(revision) { credentials.selected }
                ValueRow(
                    title = stringResource(R.string.cloudflare_title),
                    value = chosen?.kind?.displayName.orEmpty(),
                    subtitle = dnsAPISummary(credentials, DNSCredentialTokenStore(secrets), revision),
                    onClick = { page = PAGE_CLOUDFLARE },
                    showDivider = false,
                )
            }
        }
        item {
            val context = LocalContext.current
            GroupedSection(footer = stringResource(R.string.settings_system_footer)) {
                ActionRow(
                    text = stringResource(R.string.settings_system),
                    showDivider = false,
                    onClick = {
                        context.startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", context.packageName, null),
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                    },
                )
            }
        }
        item {
            GroupedSection {
                ActionRow(
                    text = stringResource(R.string.tour_take),
                    onClick = { AppTourRequests.request() },
                    showDivider = false,
                )
            }
        }
        item { ProjectLinksSection() }
        item { AppUpdateRows(appUpdates, revision) }
        item {
            GroupedSection {
                PageRow(stringResource(R.string.settings_licenses), showDivider = false) {
                    page = PAGE_LICENSES
                }
            }
        }
    }
}

@Composable
private fun AppUpdateRows(model: AppUpdateViewModel, revision: Long) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val state by model.state.collectAsState()
    val auto = remember(revision) { model.autoCheckEnabled() }

    GroupedSection(
        header = stringResource(R.string.updates_app_header),
        note = stringResource(R.string.updates_app_footer, model.version),
    ) {
        when (val current = state) {
            is AppUpdateViewModel.State.Available -> {
                ValueRow(
                    title = stringResource(R.string.updates_app_available, current.release.versionName),
                    value = null,
                    subtitle = current.release.notes,
                    onClick = null,
                )
                ActionRow(
                    text = stringResource(R.string.updates_app_download),
                    onClick = {
                        runCatching {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(current.release.url)))
                        }
                    },
                )
                current.release.sha256?.let { hash ->
                    ValueRow(
                        title = stringResource(R.string.updates_app_checksum),
                        value = null,
                        subtitle = hash,
                        onClick = null,
                    )
                }
            }
            else -> ActionRow(
                text = stringResource(
                    when (current) {
                        AppUpdateViewModel.State.Checking -> R.string.updates_app_checking
                        AppUpdateViewModel.State.UpToDate -> R.string.updates_app_up_to_date
                        AppUpdateViewModel.State.Failed -> R.string.updates_app_failed
                        else -> R.string.updates_app_check
                    }
                ),
                onClick = { model.checkNow(scope) },
                enabled = current != AppUpdateViewModel.State.Checking,
            )
        }
        ToggleRow(
            title = stringResource(R.string.updates_app_auto),
            checked = auto,
            onCheckedChange = { on -> model.setAutoCheck(on) },
            showDivider = false,
        )
    }
}

private const val PAGE_APPEARANCE = "appearance"
private const val PAGE_APPEARANCE_APP = "appearance.app"
private const val PAGE_APPEARANCE_CARDS = "appearance.cards"
private const val PAGE_APPEARANCE_CHARTS = "appearance.charts"
private const val PAGE_APPEARANCE_SERVER = "appearance.server"
private const val PAGE_SECTIONS = "sections"
private const val PAGE_SECURITY = "security"
private const val PAGE_NOTIFICATIONS = "notifications"
private const val PAGE_OPERATIONS = "operations"
private const val PAGE_CLOUDFLARE = "cloudflare"
private const val PAGE_RANGES = "ranges"
private const val PAGE_METRICS = "metrics"
private const val PAGE_LICENSES = "licenses"
private const val PAGE_LICENSE = "license"

private const val SUPPORT_CHAT = "https://discord.gg/RsMMRPgzhK"
private const val WEBSITE = "https://gryonix.com"
private const val SOURCE_REPOSITORY = "https://github.com/gryonix/Nexus"

@Composable
private fun ProjectLinksSection() {
    GroupedSection {
        LinkRow(stringResource(R.string.license_website), WEBSITE)
        LinkRow("GitHub", SOURCE_REPOSITORY)
        LinkRow("Discord", SUPPORT_CHAT, showDivider = false)
    }
}

@Composable
private fun LinkRow(text: String, url: String, showDivider: Boolean = true) {
    val context = LocalContext.current
    ActionRow(
        text = text,
        showDivider = showDivider,
        onClick = {
            context.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        },
    )
}

@Composable
private fun LicenseSettingsRow(onOpen: () -> Unit) {
    val status by LicenseGate.status.collectAsState()
    GroupedSection {
        ValueRow(
            title = stringResource(R.string.license_title),
            value = licenseStatusText(status),
            onClick = onOpen,
            showDivider = false,
        )
    }
}

@Composable
private fun PageRow(title: String, showDivider: Boolean = true, onClick: () -> Unit) {
    GroupedRow(
        showDivider = showDivider,
        onClick = onClick,
        trailing = { DisclosureChevron() },
    ) {
        RowLabel(title)
    }
}

@Composable
private fun dnsAPISummary(
    credentials: DNSCredentials,
    tokens: DNSCredentialTokenStore,
    revision: Long,
): String {
    val all = remember(revision) { credentials.adoptStoredTokensIfNeeded(); credentials.all }
    val withTokens = remember(revision, all.size) { all.count { tokens.token(it) != null } }
    return when {
        withTokens == 0 -> stringResource(R.string.cloudflare_none)
        all.size == 1 -> stringResource(R.string.cloudflare_one_account, all.first().name)
        else -> stringResource(R.string.dns_tokens_count, withTokens, all.size)
    }
}

@Composable
private fun AppearancePage(store: SettingsStore, tabs: TabBarSettings, onPage: (String) -> Unit) {
    val revision by store.revision.collectAsState()
    val override by tabs.groupServicesOverride.collectAsState()
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item {
            GroupedSection {
                val accent = remember(revision) { store.appAccent() }
                ValueRow(
                    title = stringResource(R.string.settings_appearance_app),
                    value = stringResource(accent.labelRes),
                    onClick = { onPage(PAGE_APPEARANCE_APP) },
                )
                val size = remember(revision) {
                    ServerCardColumns.of(store.string(ServerCardColumns.KEY))
                }
                ValueRow(
                    title = stringResource(R.string.settings_cards),
                    value = stringResource(
                        if (size.cardSize == ServerCardSize.WIDE) R.string.card_wide
                        else R.string.card_compact
                    ),
                    onClick = { onPage(PAGE_APPEARANCE_CARDS) },
                )
                val offered = remember(revision) { OfferedCharts.of(store) }
                ValueRow(
                    title = stringResource(R.string.settings_appearance_charts),
                    value = stringResource(
                        R.string.settings_appearance_charts_summary,
                        offered.ranges.size, HistoryRange.entries.size,
                        offered.metrics.size, HistoryMetric.entries.size,
                    ),
                    onClick = { onPage(PAGE_APPEARANCE_CHARTS) },
                )
                ValueRow(
                    title = stringResource(R.string.settings_server_screen),
                    value = stringResource(
                        when (override) {
                            null -> R.string.settings_group_automatic
                            true -> R.string.settings_group_always
                            else -> R.string.settings_group_never
                        }
                    ),
                    onClick = { onPage(PAGE_APPEARANCE_SERVER) },
                    showDivider = false,
                )
            }
        }
    }
}

@Composable
private fun AppearanceAppPage(store: SettingsStore) {
    val revision by store.revision.collectAsState()
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item { AppIconPicker() }
        item {
            GroupedSection(footer = stringResource(R.string.settings_accent_footer)) {
                AccentRows(store, revision)
            }
        }
        item {
            GroupedSection(footer = stringResource(R.string.settings_haptics_footer)) {
                val on = remember(revision) { store.hapticsEnabled() }
                ToggleRow(
                    title = stringResource(R.string.settings_haptics),
                    checked = on,
                    onCheckedChange = { store.setHapticsEnabled(it) },
                    showDivider = false,
                )
            }
        }
    }
}

@Composable
private fun AppearanceCardsPage(store: SettingsStore) {
    val revision by store.revision.collectAsState()
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item {
            GroupedSection(
                header = stringResource(R.string.settings_cards),
                note = stringResource(R.string.settings_cards_footer),
            ) {
                CardSizeRow(store, revision)
                IndicatorRow(store, revision)
            }
        }
        item {
            GroupedSection(
                header = stringResource(R.string.settings_wake_header),
                note = stringResource(R.string.settings_wake_note),
            ) {
                WakeDelayRow(store, revision)
            }
        }
        item {
            GroupedSection(
                header = stringResource(R.string.settings_connection_header),
                note = stringResource(R.string.settings_connection_note),
            ) {
                ConnectionWaitRows(store, revision)
            }
        }
    }
}

@Composable
internal fun ConnectionWaitRows(store: SettingsStore, revision: Long) {
    val silence = remember(revision) { ConnectionSettings.silence(store) }
    val reconnect = remember(revision) { ConnectionSettings.reconnect(store) }
    var editing by remember { mutableStateOf<String?>(null) }
    ConnectionWaitRow(
        title = stringResource(R.string.settings_connection_silence),
        current = silence,
        presets = ConnectionSettings.SILENCES,
        onPick = { store.setString(ConnectionSettings.SILENCE_KEY, it.toString()) },
        onOther = { editing = ConnectionSettings.SILENCE_KEY },
    )
    ConnectionWaitRow(
        title = stringResource(R.string.settings_connection_reconnect),
        current = reconnect,
        presets = ConnectionSettings.RECONNECTS,
        onPick = { store.setString(ConnectionSettings.RECONNECT_KEY, it.toString()) },
        onOther = { editing = ConnectionSettings.RECONNECT_KEY },
        showDivider = false,
    )
    editing?.let { key ->
        val silenceKey = key == ConnectionSettings.SILENCE_KEY
        CustomSecondsAlert(
            title = stringResource(
                if (silenceKey) R.string.settings_connection_silence else R.string.settings_connection_reconnect
            ),
            range = if (silenceKey) ConnectionSettings.SILENCE_RANGE else ConnectionSettings.RECONNECT_RANGE,
            onSet = { store.setString(key, it.toString()) },
            onDismiss = { editing = null },
        )
    }
}

@Composable
private fun ConnectionWaitRow(
    title: String,
    current: Int,
    presets: List<Int>,
    onPick: (Int) -> Unit,
    onOther: () -> Unit,
    showDivider: Boolean = true,
) {
    val never = stringResource(R.string.settings_group_never)
    val label = { seconds: Int -> if (seconds == 0) never else ConnectionSettings.title(seconds) }
    val shown = if (current in presets) presets else presets + current
    ChoiceRow(
        title = title,
        value = label(current),
        showDivider = showDivider,
        options = shown.map { seconds -> label(seconds) to { onPick(seconds) } } +
            (stringResource(R.string.connection_other_time) to onOther),
    )
}

@Composable
private fun WakeDelayRow(store: SettingsStore, revision: Long) {
    val current = remember(revision) { WakeButtonSettings.delay(store) }
    ChoiceRow(
        title = stringResource(R.string.settings_wake_after),
        value = WakeButtonSettings.title(current),
        showDivider = false,
        options = WakeButtonSettings.DELAYS.map { seconds ->
            WakeButtonSettings.title(seconds) to { store.setString(WakeButtonSettings.KEY, seconds.toString()) }
        },
    )
}

@Composable
private fun AppearanceChartsPage(store: SettingsStore, onPage: (String) -> Unit) {
    val revision by store.revision.collectAsState()
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item {
            GroupedSection(
                header = stringResource(R.string.settings_charts),
                note = stringResource(R.string.settings_charts_footer),
            ) {
                HistoryPresentationRow(store, revision)
                ChartScaleRow(store, revision)
            }
        }
        item {
            GroupedSection(
                header = stringResource(R.string.settings_offers),
                note = stringResource(R.string.settings_offers_footer),
            ) {
                val offered = remember(revision) { OfferedCharts.of(store) }
                CountRow(
                    stringResource(R.string.settings_offered_ranges),
                    offered.ranges.size, HistoryRange.entries.size,
                ) { onPage(PAGE_RANGES) }
                CountRow(
                    stringResource(R.string.settings_offered_metrics),
                    offered.metrics.size, HistoryMetric.entries.size,
                    showDivider = false,
                ) { onPage(PAGE_METRICS) }
            }
        }
    }
}

@Composable
private fun AppearanceServerScreenPage(tabs: TabBarSettings) {
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item {
            GroupedSection(
                header = stringResource(R.string.settings_server_screen),
                note = stringResource(R.string.settings_server_screen_footer),
            ) {
                ServerScreenRows(tabs)
            }
        }
    }
}

/** What is on the bar, and in which order */
@Composable
private fun SectionsPage(tabs: TabBarSettings, store: SettingsStore) {
    val order by tabs.order.collectAsState()
    val hidden by tabs.hidden.collectAsState()
    val revision by store.revision.collectAsState()
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item {
            GroupedSection(
                footer = stringResource(R.string.settings_sections_footer),
                dividerInset = 46.dp,
            ) {
                order.forEach { tab ->
                    val onBar = remember(revision, hidden) {
                        ShellSectionVisibility.isOnBar(tab, tabs, store)
                    }
                    SectionRow(
                        tab = tab,
                        onBar = onBar,
                        canMoveUp = tabs.canMoveUp(tab),
                        canMoveDown = tabs.canMoveDown(tab),
                        onToggle = { ShellSectionVisibility.setOnBar(it, tab, tabs, store) },
                        onUp = { tabs.moveUp(tab) },
                        onDown = { tabs.moveDown(tab) },
                        showDivider = tab != order.last(),
                    )
                }
            }
        }
    }
}

@Composable
private fun SecurityPage(store: SettingsStore) {
    val revision by store.revision.collectAsState()
    val security = remember(store) { SecuritySettings(store) }
    val unlock = rememberUnlock(stringResource(R.string.settings_security_unlock_reason))
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        if (unlock.state != UnlockState.UNLOCKED) {
            item { LockedNotice(unlock) }
            return@LazyColumn
        }
        item {
            GroupedSection(footer = stringResource(R.string.settings_security_footer)) {
                GateRow(security, GatedAction.ACCESS_SCREEN, R.string.settings_gate_access, revision)
                GateRow(security, GatedAction.REVEAL, R.string.settings_gate_reveal, revision)
                GateRow(
                    security,
                    GatedAction.EXPORT,
                    R.string.settings_gate_export,
                    revision,
                    showDivider = false,
                )
            }
        }
    }
}

private enum class UnlockState { UNLOCKING, UNLOCKED, FAILED }

private class Unlock(val state: UnlockState, val retry: () -> Unit)

/** Asks for the device unlock once, on entry */
@Composable
private fun rememberUnlock(reason: String): Unlock {
    val gate = LocalDeviceGate.current
    val scope = rememberCoroutineScope()
    var state by remember { mutableStateOf(UnlockState.UNLOCKING) }
    val ask: () -> Unit = {
        state = UnlockState.UNLOCKING
        scope.launch { state = if (gate.confirm(reason)) UnlockState.UNLOCKED else UnlockState.FAILED }
    }
    LaunchedEffect(Unit) { ask() }
    return Unlock(state, ask)
}

@Composable
private fun LockedNotice(unlock: Unlock) {
    GroupedSection {
        GroupedRow(showDivider = unlock.state == UnlockState.FAILED) {
            RowLabel(
                stringResource(
                    if (unlock.state == UnlockState.FAILED) R.string.settings_security_not_unlocked
                    else R.string.settings_security_unlocking,
                ),
            )
        }
        if (unlock.state == UnlockState.FAILED) {
            GroupedRow(showDivider = false) {
                PlainButton(text = stringResource(R.string.notice_retry), onClick = unlock.retry)
            }
        }
    }
}

@Composable
private fun DNSAPIPage(
    credentials: DNSCredentials,
    tokens: DNSCredentialTokenStore,
    store: SettingsStore,
) {
    val revision by store.revision.collectAsState()
    val all = remember(revision) { credentials.adoptStoredTokensIfNeeded(); credentials.all }
    var editing by remember { mutableStateOf<DNSCredential?>(null) }
    var adding by remember { mutableStateOf(false) }
    val sort = remember(revision) { dnsCredentialSort(store) }
    val rows = remember(revision, all.size, sort) { sortDNSCredentials(all, sort) }

    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        if (all.size > 1) {
            item {
                GroupedSection {
                    ChoiceRow(
                        title = stringResource(R.string.dns_sort),
                        value = stringResource(dnsSortLabel(sort)),
                        showDivider = false,
                        options = DNS_SORTS.map { order ->
                            stringResource(dnsSortLabel(order)) to {
                                store.setString(DNS_SORT_KEY, order)
                            }
                        },
                    )
                }
            }
        }
        item {
            GroupedSection(
                footer = stringResource(
                    if (all.isEmpty()) R.string.dns_no_tokens else R.string.dns_tokens_hint
                )
            ) {
                rows.forEach { credential ->
                    val has = remember(revision, credential.id) { tokens.token(credential) != null }
                    GroupedRow(
                        showDivider = true,
                        onClick = { credentials.selectedID = credential.id },
                        trailing = {
                            if (credential.id == credentials.selectedID) {
                                Icon(
                                    Icons.Filled.Check,
                                    contentDescription = null,
                                    tint = Gryonix.colors.accent,
                                    modifier = Modifier.size(20.dp),
                                )
                            }
                            IconButton(
                                onClick = { editing = credential },
                                modifier = Modifier.size(32.dp),
                            ) {
                                Icon(
                                    Icons.Filled.Edit,
                                    contentDescription = stringResource(R.string.dns_edit_token),
                                    tint = Gryonix.colors.accent,
                                    modifier = Modifier.size(20.dp),
                                )
                            }
                        },
                    ) {
                        RowLabel(
                            title = credential.name,
                            subtitle = credential.kind.displayName + " · " + stringResource(
                                if (has) R.string.cloudflare_dns_only else R.string.cloudflare_none
                            ),
                        )
                    }
                }
                ActionRow(
                    text = stringResource(R.string.dns_add_token),
                    onClick = { adding = true },
                    showDivider = false,
                )
            }
        }
    }

    if (adding) {
        DNSCredentialSheet(credentials, tokens, credential = null) { adding = false }
    }

    editing?.let { credential ->
        DNSCredentialSheet(credentials, tokens, credential) { editing = null }
    }
}

private const val DNS_SORT_KEY = "dns.credentials.sort"
private const val DNS_SORT_ADDED = "added"
private const val DNS_SORT_PROVIDER = "provider"
private val DNS_SORTS = listOf(DNS_SORT_ADDED, DNS_SORT_PROVIDER)

private fun dnsCredentialSort(store: SettingsStore): String =
    store.string(DNS_SORT_KEY)?.takeIf { it in DNS_SORTS } ?: DNS_SORT_ADDED

private fun dnsSortLabel(sort: String): Int =
    if (sort == DNS_SORT_PROVIDER) R.string.dns_sort_provider else R.string.dns_sort_added

private fun sortDNSCredentials(all: List<DNSCredential>, sort: String): List<DNSCredential> =
    if (sort == DNS_SORT_PROVIDER) {
        all.sortedWith(compareBy({ it.kind.displayName }, { it.name.lowercase() }))
    } else {
        all
    }

@Composable
private fun DNSCredentialSheet(
    credentials: DNSCredentials,
    tokens: DNSCredentialTokenStore,
    credential: DNSCredential?,
    onClose: () -> Unit,
) {
    val id = credential?.id
    var kind by remember(id) { mutableStateOf(credential?.kind ?: DNSProviderKind.CLOUDFLARE) }
    var nameDraft by remember(id) { mutableStateOf(id?.let { credentials.storedName(it) }.orEmpty()) }
    var draft by remember(id) { mutableStateOf("") }
    var tunnelDraft by remember(id) { mutableStateOf("") }
    var hasToken by remember(id) {
        mutableStateOf(credential?.let { tokens.token(it) != null } ?: false)
    }
    var hasTunnel by remember(id) {
        mutableStateOf(credential?.let { tokens.tunnelToken(it) != null } ?: false)
    }

    IOSSheet(
        title = nameDraft.ifBlank { kind.displayName },
        onClose = onClose,
        closeLabel = stringResource(R.string.access_cancel),
        action = SheetAction(
            title = stringResource(R.string.containers_done),
            onSelect = {
                val target = credential ?: credentials.add(nameDraft, kind)
                tokens.move(target, kind)
                val saved = target.copy(kind = kind)
                if (draft.isNotBlank()) tokens.setToken(saved, draft)
                if (tunnelDraft.isNotBlank() && kind == DNSProviderKind.CLOUDFLARE) {
                    tokens.setTunnelToken(saved, tunnelDraft)
                }
                credentials.update(target.id, nameDraft, kind)
                onClose()
            },
        ),
    ) {
        GroupedSection {
            FieldRow(
                label = stringResource(R.string.cloudflare_account_name),
                value = nameDraft,
                onValueChange = { nameDraft = it },
                showDivider = true,
            )
            ChoiceRow(
                title = stringResource(R.string.wizard_publish_provider),
                value = kind.displayName,
                showDivider = false,
                options = DNSProviderKind.entries.map { option ->
                    option.displayName to { kind = option }
                },
            )
        }
        GroupedSection(footer = stringResource(kind.setupHintRes)) {
            FieldRow(
                label = stringResource(
                    if (hasToken) R.string.cloudflare_replace else kind.tokenLabelRes
                ),
                value = draft,
                onValueChange = { draft = it },
                visualTransformation = PasswordVisualTransformation(),
                showDivider = hasToken,
            )
            if (hasToken && credential != null) {
                ActionRow(
                    text = stringResource(R.string.cloudflare_forget),
                    onClick = { tokens.setToken(credential, null); hasToken = false },
                    danger = true,
                    showDivider = false,
                )
            }
        }
        if (kind == DNSProviderKind.CLOUDFLARE) {
            GroupedSection(footer = stringResource(R.string.cloudflare_tunnel_hint)) {
                FieldRow(
                    label = stringResource(
                        if (hasTunnel) R.string.cloudflare_replace else R.string.cloudflare_tunnel_label
                    ),
                    value = tunnelDraft,
                    onValueChange = { tunnelDraft = it },
                    visualTransformation = PasswordVisualTransformation(),
                    showDivider = hasTunnel,
                )
                if (hasTunnel && credential != null) {
                    ActionRow(
                        text = stringResource(R.string.cloudflare_forget),
                        onClick = { tokens.setTunnelToken(credential, null); hasTunnel = false },
                        danger = true,
                        showDivider = false,
                    )
                }
            }
        }
    }
}

@Composable
private fun SectionRow(
    tab: AppTab,
    onBar: Boolean,
    canMoveUp: Boolean,
    canMoveDown: Boolean,
    onToggle: (Boolean) -> Unit,
    onUp: () -> Unit,
    onDown: () -> Unit,
    showDivider: Boolean,
) {
    GroupedRow(
        showDivider = showDivider,
        leading = { Icon(tab.icon, contentDescription = null, modifier = Modifier.size(22.dp)) },
        trailing = {
            Row(horizontalArrangement = Arrangement.End) {
                ReorderButton(Icons.Filled.ArrowUpward, R.string.move_up, canMoveUp, onUp)
                ReorderButton(Icons.Filled.ArrowDownward, R.string.move_down, canMoveDown, onDown)
                IOSSwitch(
                    checked = onBar,
                    onCheckedChange = onToggle,
                    enabled = tab.canBeHidden,
                )
            }
        },
    ) {
        RowLabel(
            title = stringResource(tab.titleRes),
            subtitle = if (!onBar && ShellSectionVisibility.placementKey(tab) != null) {
                stringResource(R.string.inside_the_server)
            } else {
                null
            },
        )
    }
}

@Composable
private fun ReorderButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    descriptionRes: Int,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    val colors = Gryonix.colors
    IconButton(onClick = onClick, enabled = enabled, modifier = Modifier.size(32.dp)) {
        Icon(
            icon,
            contentDescription = stringResource(descriptionRes),
            tint = if (enabled) colors.accent else colors.tertiaryLabel,
            modifier = Modifier.size(22.dp),
        )
    }
}

@Composable
internal fun DemoFleetRow(store: SettingsStore, fleet: FleetRepository, revision: Long) {
    val on = remember(revision) { fleet.isDemo }
    // Last on its plate, so no hairline under it.
    GroupedRow(
        showDivider = false,
        trailing = {
            IOSSwitch(
                checked = on,
                onCheckedChange = { wanted ->
                    store.setString(DemoDeployments.COUNT_KEY, if (wanted) DemoDeployments.FULL_COUNT else "0")
                    fleet.reload()
                },
            )
        },
    ) {
        RowLabel(
            stringResource(R.string.demo_fleet),
            stringResource(R.string.demo_fleet_hint),
        )
    }
}

@Composable
private fun CardSizeRow(store: SettingsStore, revision: Long) {
    val current = remember(revision) { ServerCardColumns.of(store.string(ServerCardColumns.KEY)) }
    ChoiceRow(
        title = stringResource(R.string.settings_default_card_size),
        value = stringResource(
            if (current.cardSize == ServerCardSize.WIDE) R.string.card_wide else R.string.card_compact
        ),
        options = ServerCardColumns.entries.map { option ->
            stringResource(
                if (option.cardSize == ServerCardSize.WIDE) R.string.card_wide else R.string.card_compact
            ) to { store.setString(ServerCardColumns.KEY, option.raw) }
        }
    )
}

@Composable
private fun CountRow(
    title: String,
    on: Int,
    of: Int,
    showDivider: Boolean = true,
    onClick: () -> Unit,
) {
    ValueRow(
        title = title,
        value = stringResource(R.string.settings_offers_count, on, of),
        showDivider = showDivider,
        onClick = onClick,
    )
}

/** The periods on offer */
@Composable
private fun OfferedRangesPage(store: SettingsStore) {
    val revision by store.revision.collectAsState()
    val preferences = remember(store) { MetricsPreferences(store) }
    val offered = remember(revision) { preferences.ranges }
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item {
            GroupedSection(footer = stringResource(R.string.settings_offers_footer)) {
                HistoryRange.entries.forEach { candidate ->
                    val on = candidate in offered
                    ToggleRow(
                        title = stringResource(candidate.titleRes),
                        checked = on,
                        enabled = !on || offered.size > 1,
                        onCheckedChange = { preferences.setRange(candidate, it) },
                        showDivider = candidate != HistoryRange.entries.last(),
                    )
                }
            }
        }
    }
}

/** The metrics on offer, by the same rule */
@Composable
private fun OfferedMetricsPage(store: SettingsStore) {
    val revision by store.revision.collectAsState()
    val preferences = remember(store) { MetricsPreferences(store) }
    val offered = remember(revision) { preferences.metrics }
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item {
            GroupedSection(footer = stringResource(R.string.settings_offers_footer)) {
                HistoryMetric.entries.forEach { candidate ->
                    val on = candidate in offered
                    ToggleRow(
                        title = stringResource(candidate.titleRes),
                        checked = on,
                        enabled = !on || offered.size > 1,
                        onCheckedChange = { preferences.setMetric(candidate, it) },
                        showDivider = candidate != HistoryMetric.entries.last(),
                    )
                }
            }
        }
    }
}

/** Where a machine's history opens — see `HistoryPresentation` */
@Composable
private fun HistoryPresentationRow(store: SettingsStore, revision: Long) {
    val inline = remember(revision) {
        HistoryPresentation.inline(store.boolean(HistoryPresentation.INLINE_KEY))
    }
    ChoiceRow(
        title = stringResource(R.string.metrics_history),
        value = stringResource(
            if (inline) R.string.settings_history_inline else R.string.settings_history_separate
        ),
        options = listOf(
            stringResource(R.string.settings_history_separate) to
                { store.setBoolean(HistoryPresentation.INLINE_KEY, false) },
            stringResource(R.string.settings_history_inline) to
                { store.setBoolean(HistoryPresentation.INLINE_KEY, true) },
        ),
    )
}

@Composable
private fun ChartScaleRow(store: SettingsStore, revision: Long) {
    val auto = remember(revision) { ChartScale.auto(store.boolean(ChartScale.AUTO_KEY)) }
    ChoiceRow(
        title = stringResource(R.string.settings_chart_scale),
        value = stringResource(
            if (auto) R.string.settings_chart_scale_auto else R.string.settings_chart_scale_absolute
        ),
        showDivider = false,
        options = listOf(
            stringResource(R.string.settings_chart_scale_auto) to
                { store.setBoolean(ChartScale.AUTO_KEY, true) },
            stringResource(R.string.settings_chart_scale_absolute) to
                { store.setBoolean(ChartScale.AUTO_KEY, false) },
        ),
    )
}

/** What the SERVER screen does with its own two lists */
@Composable
private fun ServerScreenRows(tabs: TabBarSettings) {
    val collapsible by tabs.sitesCollapsible.collectAsState()
    val override by tabs.groupServicesOverride.collectAsState()
    ToggleRow(
        title = stringResource(R.string.settings_sites_collapsible),
        checked = collapsible,
        onCheckedChange = { tabs.setSitesCollapsible(it) },
    )
    ChoiceRow(
        title = stringResource(R.string.settings_group_services),
        value = stringResource(
            when (override) {
                null -> R.string.settings_group_automatic
                true -> R.string.settings_group_always
                else -> R.string.settings_group_never
            }
        ),
        showDivider = false,
        options = listOf(
            stringResource(R.string.settings_group_automatic) to { tabs.setGroupServicesOverride(null) },
            stringResource(R.string.settings_group_always) to { tabs.setGroupServicesOverride(true) },
            stringResource(R.string.settings_group_never) to { tabs.setGroupServicesOverride(false) },
        ),
    )
}

@Composable
private fun AccentRows(store: SettingsStore, revision: Long) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    val current = remember(revision) { store.appAccent() }
    val palette = Gryonix.colors
    GroupedRow(
        onClick = { expanded = !expanded },
        showDivider = expanded,
        trailing = {
            AccentDot(current.colour(palette))
            Text(
                stringResource(current.labelRes),
                style = MaterialTheme.typography.bodyLarge,
                color = palette.secondaryLabel,
            )
            DisclosureChevron()
        },
    ) {
        RowLabel(stringResource(R.string.settings_accent))
    }
    if (expanded) {
        AppAccent.entries.forEach { candidate ->
            GroupedRow(
                onClick = { store.setAppAccent(candidate) },
                showDivider = candidate != AppAccent.entries.last(),
                leading = { AccentDot(candidate.colour(palette)) },
                trailing = {
                    if (candidate == current) {
                        Icon(
                            Icons.Filled.Check,
                            contentDescription = null,
                            tint = palette.accent,
                        )
                    }
                },
            ) {
                RowLabel(stringResource(candidate.labelRes))
            }
        }
    }
}

/** The colour, as a dot before the name */
@Composable
private fun AccentDot(colour: Color) {
    Box(
        Modifier
            .size(18.dp)
            .background(colour, CircleShape)
            .border(1.dp, Gryonix.colors.label.copy(alpha = 0.15f), CircleShape)
    )
}

/** The words the twelve accents are shown with — see `ServerCardAppearance` */
@get:StringRes
private val AppAccent.labelRes: Int
    get() = when (this) {
        AppAccent.APP -> R.string.accent_app
        AppAccent.RED -> R.string.tint_red
        AppAccent.ORANGE -> R.string.tint_orange
        AppAccent.YELLOW -> R.string.accent_yellow
        AppAccent.GREEN -> R.string.tint_green
        AppAccent.TEAL -> R.string.tint_teal
        AppAccent.PURPLE -> R.string.tint_purple
        AppAccent.PINK -> R.string.tint_pink
        AppAccent.GRAPHITE -> R.string.accent_graphite
        AppAccent.BLACK -> R.string.accent_black
        AppAccent.INDIGO -> R.string.accent_indigo
        AppAccent.BROWN -> R.string.accent_brown
    }

@Composable
private fun IndicatorRow(store: SettingsStore, revision: Long) {
    val current = remember(revision) {
        MetricsDisplaySettings.indicatorStyle(
            store.string(MetricsDisplaySettings.INDICATOR_STYLE_KEY)
        )
    }
    ChoiceRow(
        title = stringResource(R.string.card_indicator),
        value = stringResource(current.labelRes),
        showDivider = false,
        options = MetricsIndicatorStyle.entries.map { option ->
            stringResource(option.labelRes) to {
                store.setString(
                    MetricsDisplaySettings.INDICATOR_STYLE_KEY,
                    MetricsDisplaySettings.raw(option)
                )
            }
        }
    )
}

@Composable
fun ChoiceRow(
    title: String,
    value: String,
    showDivider: Boolean = true,
    options: List<Pair<String, () -> Unit>>,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        ValueRow(
            title = title,
            value = value,
            showDivider = showDivider,
            onClick = { open = true },
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEach { (label, choose) ->
                DropdownMenuItem(
                    text = { Text(label) },
                    trailingIcon = {
                        if (label == value) Icon(Icons.Filled.Check, contentDescription = null)
                    },
                    onClick = { choose(); open = false }
                )
            }
        }
    }
}

@Composable
private fun GateRow(
    security: SecuritySettings,
    action: GatedAction,
    titleRes: Int,
    revision: Long,
    showDivider: Boolean = true,
) {
    val gated = remember(revision, action) { security.isGated(action) }
    GroupedRow(
        showDivider = showDivider,
        trailing = {
            IOSSwitch(checked = gated, onCheckedChange = { security.setGated(it, action) })
        },
    ) {
        RowLabel(stringResource(titleRes))
    }
}
