package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.security.SecurityViewModel
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.StepperRow
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostSecurityAutoRules
import kotlinx.coroutines.delay
import kotlinx.serialization.json.Json

/** How long an edit waits before it is sent */
private const val SEND_AFTER_MS = 1200L

@Composable
fun SecurityAutoRulesSheet(
    deployment: Deployment,
    security: SecurityViewModel,
    /** Where the fleet-wide template lives — see [SecurityRulesTemplate] */
    store: SettingsStore,
    onClose: () -> Unit,
) {
    val state by security.state.collectAsState()
    PleaseWaitDialog(state.autoRulesBusy)
    // Filled by the first read and by a save's answer
    var draft by remember(deployment.id) {
        mutableStateOf(state.autoRules ?: HostSecurityAutoRules())
    }
    var draftLoaded by remember(deployment.id) { mutableStateOf(state.autoRules != null) }
    var saveRequested by remember(deployment.id) { mutableStateOf(false) }
    LaunchedEffect(state.autoRulesBusy, state.autoRules) {
        if (state.autoRulesBusy) return@LaunchedEffect
        val rules = state.autoRules ?: return@LaunchedEffect
        // A refused save leaves the draft alone
        if (saveRequested && state.autoRulesFailure != null) {
            saveRequested = false
            return@LaunchedEffect
        }
        if (!draftLoaded || saveRequested) {
            draft = rules
            draftLoaded = true
            saveRequested = false
        }
    }
    var newService by remember(deployment.id) { mutableStateOf("") }
    var addingCustomService by remember(deployment.id) { mutableStateOf(false) }
    var showingCountryPicker by remember { mutableStateOf(false) }
    val edited = draftLoaded && state.autoRules != null && draft != state.autoRules
    val send = {
        saveRequested = true
        security.saveAutoRules(deployment, draft)
    }
    // An edit is sent a moment after the last change
    LaunchedEffect(draft) {
        if (!edited) return@LaunchedEffect
        delay(SEND_AFTER_MS)
        send()
    }

    IOSSheet(
        title = stringResource(R.string.security_auto_title),
        // Closing before that pause elapsed still sends the edit
        onClose = {
            if (edited && !saveRequested && !state.autoRulesBusy) send()
            onClose()
        },
        closeLabel = stringResource(R.string.close),
    ) {
        state.autoRulesFailure?.let { failure ->
            GroupedSection {
                GroupedRow(showDivider = false) {
                    Text(
                        failure,
                        style = MaterialTheme.typography.bodySmall,
                        color = Gryonix.colors.warning,
                    )
                }
            }
        }
        GroupedSection(note = stringResource(R.string.security_auto_note)) {
            ToggleRow(
                title = stringResource(R.string.security_auto_on),
                checked = draft.isOn,
                onCheckedChange = { draft = draft.copy(isOn = it) },
                showDivider = false,
            )
        }

        if (draft.isOn) {
            GroupedSection(
                header = stringResource(R.string.security_auto_countries),
                note = stringResource(R.string.security_auto_countries_note),
            ) {
                ValueRow(
                    title = stringResource(R.string.security_auto_countries),
                    value = if (draft.countries.isEmpty()) "—" else draft.countries.size.toString(),
                    onClick = { showingCountryPicker = true },
                )
                if (showingCountryPicker) {
                    CountryRegionPickerSheet(
                        codes = draft.countries,
                        onCodesChange = { draft = draft.copy(countries = it) },
                        store = store,
                        onClose = { showingCountryPicker = false },
                    )
                }
                ChoiceRow(
                    title = stringResource(R.string.security_auto_direction),
                    value = stringResource(
                        if (draft.countriesAreAllowlist) {
                            R.string.security_auto_only_allowed
                        } else {
                            R.string.security_auto_blocked
                        },
                    ),
                    showDivider = state.autoRules?.geoIPAvailable == false,
                    options = listOf(
                        stringResource(R.string.security_auto_blocked) to {
                            draft = draft.copy(countriesAreAllowlist = false)
                        },
                        stringResource(R.string.security_auto_only_allowed) to {
                            draft = draft.copy(countriesAreAllowlist = true)
                        },
                    ),
                )
                if (state.autoRules?.geoIPAvailable == false) {
                    GroupedRow(showDivider = false) {
                        Text(
                            stringResource(R.string.security_auto_no_geoip),
                            style = MaterialTheme.typography.bodySmall,
                            color = Gryonix.colors.warning,
                        )
                    }
                }
            }

            val engineDefault = stringResource(R.string.security_auto_engine_default)
            GroupedSection(
                header = stringResource(R.string.security_auto_tries),
                note = stringResource(R.string.security_auto_tries_note),
            ) {
                StepperRow(
                    label = stringResource(R.string.security_auto_failures),
                    value = draft.attemptThreshold,
                    range = 0..100,
                    onChange = { draft = draft.copy(attemptThreshold = it) },
                    showDivider = false,
                    format = { if (it == 0) engineDefault else it.toString() },
                )
            }

            GroupedSection(
                header = stringResource(R.string.security_auto_reach),
                note = stringResource(R.string.security_auto_reach_note),
            ) {
                GroupedRow(
                    trailing = {
                        Text(
                            stringResource(R.string.security_auto_not_automatic),
                            style = MaterialTheme.typography.bodySmall,
                            color = Gryonix.colors.secondaryLabel,
                        )
                    },
                ) {
                    RowLabel(stringResource(R.string.security_auto_subnet))
                }
                GroupedRow {
                    Text(
                        stringResource(R.string.security_auto_subnet_unavailable),
                        style = MaterialTheme.typography.bodySmall,
                        color = Gryonix.colors.secondaryLabel,
                    )
                }
                ChoiceRow(
                    title = stringResource(R.string.security_auto_duration),
                    value = when (draft.banSeconds) {
                        4L * 3600 -> stringResource(R.string.security_block_4h)
                        24L * 3600 -> stringResource(R.string.security_block_24h)
                        7L * 24 * 3600 -> stringResource(R.string.security_auto_week)
                        UNTIL_LIFTED_SECONDS -> stringResource(R.string.security_forever)
                        else -> engineDefault
                    },
                    showDivider = false,
                    options = listOf(
                        engineDefault to { draft = draft.copy(banSeconds = 0) },
                        stringResource(R.string.security_block_4h) to {
                            draft = draft.copy(banSeconds = 4L * 3600)
                        },
                        stringResource(R.string.security_block_24h) to {
                            draft = draft.copy(banSeconds = 24L * 3600)
                        },
                        stringResource(R.string.security_auto_week) to {
                            draft = draft.copy(banSeconds = 7L * 24 * 3600)
                        },
                        stringResource(R.string.security_forever) to {
                            draft = draft.copy(banSeconds = UNTIL_LIFTED_SECONDS)
                        },
                    ),
                )
            }

            GroupedSection(
                header = stringResource(R.string.security_auto_services),
                note = stringResource(R.string.security_auto_services_note),
            ) {
                draft.services.forEachIndexed { index, rule ->
                    StepperRow(
                        label = rule.service,
                        value = rule.attemptThreshold,
                        range = 0..100,
                        onChange = { value ->
                            draft = draft.copy(
                                services = draft.services.toMutableList().also {
                                    it[index] = rule.copy(attemptThreshold = value)
                                },
                            )
                        },
                        format = { if (it == 0) engineDefault else it.toString() },
                    )
                }
                fun addService(raw: String) {
                    val name = raw.trim().lowercase()
                    if (name.isNotEmpty() && draft.services.none { it.service == name }) {
                        draft = draft.copy(
                            services = draft.services + HostSecurityAutoRules.ServiceRule(name),
                        )
                    }
                }
                if (addingCustomService) {
                    FieldRow(
                        label = stringResource(R.string.security_auto_service),
                        value = newService,
                        placeholder = "smtp",
                        onValueChange = { newService = it },
                    )
                    ActionRow(
                        text = stringResource(R.string.security_auto_add_service),
                        enabled = newService.isNotBlank(),
                        showDivider = false,
                        onClick = {
                            addService(newService)
                            newService = ""
                            addingCustomService = false
                        },
                    )
                } else {
                    var openServiceMenu by remember { mutableStateOf(false) }
                    Box {
                        ActionRow(
                            text = stringResource(R.string.security_auto_add_service),
                            showDivider = false,
                            leading = {
                                Icon(
                                    Icons.Filled.Add,
                                    contentDescription = null,
                                    tint = Gryonix.colors.accent,
                                    modifier = Modifier.size(20.dp),
                                )
                            },
                            onClick = { openServiceMenu = true },
                        )
                        DropdownMenu(expanded = openServiceMenu, onDismissRequest = { openServiceMenu = false }) {
                            DropdownMenuItem(
                                text = { Text("SSH") },
                                enabled = draft.services.none { it.service == "ssh" },
                                onClick = { addService("ssh"); openServiceMenu = false },
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.security_auto_service_website)) },
                                enabled = draft.services.none { it.service == "http" },
                                onClick = { addService("http"); openServiceMenu = false },
                            )
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.security_auto_service_other)) },
                                onClick = { addingCustomService = true; openServiceMenu = false },
                            )
                        }
                    }
                }
            }
        }

        GroupedSection(note = stringResource(R.string.security_auto_template_note)) {
            ActionRow(
                text = stringResource(R.string.security_auto_save_template),
                onClick = { SecurityRulesTemplate.save(store, draft) },
            )
            val template = SecurityRulesTemplate.load(store)
            ActionRow(
                text = stringResource(R.string.security_auto_use_template),
                enabled = template != null,
                showDivider = false,
                onClick = { template?.let { draft = it } },
            )
        }
    }
}

object SecurityRulesTemplate {
    private const val KEY = "security.autoRulesTemplate"
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun save(store: SettingsStore, rules: HostSecurityAutoRules) {
        store.setString(KEY, json.encodeToString(StoredRules.serializer(), StoredRules.of(rules)))
    }

    fun load(store: SettingsStore): HostSecurityAutoRules? {
        val text = store.string(KEY)?.takeIf { it.isNotEmpty() } ?: return null
        return runCatching {
            json.decodeFromString(StoredRules.serializer(), text).asRules()
        }.getOrNull()
    }

    /** The stored shape */
    @kotlinx.serialization.Serializable
    private data class StoredRules(
        val isOn: Boolean = false,
        val countries: List<String> = emptyList(),
        val countriesAreAllowlist: Boolean = false,
        val attemptThreshold: Int = 0,
        val attemptWindowMinutes: Int = 0,
        val bansSubnet: Boolean = false,
        val banSeconds: Long = 0,
        val services: List<StoredService> = emptyList(),
    ) {
        fun asRules() = HostSecurityAutoRules(
            isOn = isOn,
            countries = countries,
            countriesAreAllowlist = countriesAreAllowlist,
            attemptThreshold = attemptThreshold,
            attemptWindowMinutes = attemptWindowMinutes,
            bansSubnet = bansSubnet,
            banSeconds = banSeconds,
            services = services.map {
                HostSecurityAutoRules.ServiceRule(it.service, it.attemptThreshold, it.banSeconds)
            },
        )

        companion object {
            fun of(rules: HostSecurityAutoRules) = StoredRules(
                isOn = rules.isOn,
                countries = rules.countries,
                countriesAreAllowlist = rules.countriesAreAllowlist,
                attemptThreshold = rules.attemptThreshold,
                attemptWindowMinutes = rules.attemptWindowMinutes,
                bansSubnet = rules.bansSubnet,
                banSeconds = rules.banSeconds,
                services = rules.services.map {
                    StoredService(it.service, it.attemptThreshold, it.banSeconds)
                },
            )
        }
    }

    @kotlinx.serialization.Serializable
    private data class StoredService(
        val service: String,
        val attemptThreshold: Int = 0,
        val banSeconds: Long = 0,
    )
}
