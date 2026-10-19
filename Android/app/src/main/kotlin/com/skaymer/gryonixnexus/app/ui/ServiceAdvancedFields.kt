package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.configurator.ConfiguratorForm
import com.skaymer.gryonixnexus.app.configurator.ConfiguratorViewModel
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.catalog.ServiceHostnames
import com.skaymer.gryonixnexus.catalog.applyingHostnames
import com.skaymer.gryonixnexus.catalog.namedHostnames
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import com.skaymer.gryonixnexus.catalog.AutheliaDefaults
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.services.AutheliaService

/** One service's own settings, as they appear under `AdvancedSection` */
@Composable
fun ColumnScope.ServiceAdvancedFields(
    model: ConfiguratorViewModel,
    form: ConfiguratorForm,
    id: ServiceID,
    showDivider: Boolean,
) {
    val settings = form.serviceSettings
    fun edit(change: (ServiceSettings) -> ServiceSettings) =
        model.update { it.copy(serviceSettings = change(it.serviceSettings)) }

    if (ServiceHostnames.settings[id] != null) {
        OwnAddressRow(
            label = stringResource(R.string.wizard_service_domain, displayName(id)),
            value = ServiceHostnames.settings[id]?.get?.invoke(settings).orEmpty(),
            onValueChange = { name ->
                edit { it.applyingHostnames(it.namedHostnames + (id to name)) }
            },
            placeholder = defaultHostname(id, form.domain, form.services),
        )
    }
    when (id) {
        ServiceID.MAILCOW, ServiceID.MAILU, ServiceID.DOCKER_MAILSERVER ->
            ValueRow(
                title = stringResource(R.string.wizard_mail_domain),
                value = mailHostname(form.domain),
                onClick = null,
                showDivider = showDivider,
            )

        ServiceID.VAULTWARDEN -> ToggleRow(
            title = stringResource(R.string.wizard_open_registration),
            checked = settings.vaultwardenAllowSignups,
            onCheckedChange = { on -> edit { it.copy(vaultwardenAllowSignups = on) } },
            showDivider = showDivider,
        )

        ServiceID.FORGEJO -> PortFieldRow(
            label = stringResource(R.string.wizard_git_ssh_port),
            value = settings.forgejoSSHPort,
            onValue = { port -> edit { it.copy(forgejoSSHPort = port) } },
            showDivider = showDivider,
        )

        ServiceID.GITLAB -> PortFieldRow(
            label = stringResource(R.string.wizard_git_ssh_port),
            value = settings.gitlabSSHPort,
            onValue = { port -> edit { it.copy(gitlabSSHPort = port) } },
            showDivider = showDivider,
        )

        ServiceID.AUTHELIA -> {
            val candidates = autheliaCandidates(form)
            if (candidates.isEmpty()) {
                InfoRow(stringResource(R.string.wizard_authelia_empty), showDivider)
            } else {
                ToggleRow(
                    title = stringResource(R.string.wizard_authelia_all),
                    checked = settings.autheliaProtectedServices.containsAll(candidates),
                    onCheckedChange = { on ->
                        edit {
                            it.copy(
                                autheliaProtectedServices = if (on) {
                                    it.autheliaProtectedServices + candidates
                                } else {
                                    AutheliaDefaults.PROTECTED
                                },
                            )
                        }
                    },
                )
                candidates.forEachIndexed { index, candidate ->
                    ToggleRow(
                        title = displayName(candidate),
                        subtitle = stringResource(R.string.wizard_authelia_breaks_app)
                            .takeIf { candidate in AutheliaService.BREAKS_APP_CLIENTS },
                        checked = candidate in settings.autheliaProtectedServices,
                        onCheckedChange = { on ->
                            edit {
                                it.copy(
                                    autheliaProtectedServices = if (on) {
                                        it.autheliaProtectedServices + candidate
                                    } else {
                                        it.autheliaProtectedServices - candidate
                                    },
                                )
                            }
                        },
                        showDivider = showDivider || index != candidates.lastIndex,
                    )
                }
            }
        }

        ServiceID.PIHOLE -> {
            ToggleRow(
                title = stringResource(R.string.wizard_pihole_network),
                checked = settings.piholeServesNetwork,
                onCheckedChange = { on -> edit { it.copy(piholeServesNetwork = on) } },
            )
            InfoRow(
                stringResource(
                    if (settings.piholeServesNetwork) {
                        R.string.wizard_pihole_open_resolver
                    } else {
                        R.string.wizard_pihole_loopback
                    },
                ),
                showDivider,
            )
        }

        ServiceID.MINECRAFT_JAVA -> {
            FlavourRow(
                value = settings.minecraftJavaFlavour,
                onChoose = { flavour -> edit { it.copy(minecraftJavaFlavour = flavour) } },
            )
            FieldRow(
                label = stringResource(R.string.wizard_minecraft_version),
                value = settings.minecraftJavaVersion,
                onValueChange = { version -> edit { it.copy(minecraftJavaVersion = version) } },
                placeholder = "1.21.4",
            )
            PortFieldRow(
                label = stringResource(R.string.wizard_minecraft_memory),
                value = settings.minecraftJavaMemoryMB,
                onValue = { mb -> edit { it.copy(minecraftJavaMemoryMB = mb) } },
            )
            PortFieldRow(
                label = stringResource(R.string.wizard_minecraft_port),
                value = settings.minecraftJavaPort,
                onValue = { port -> edit { it.copy(minecraftJavaPort = port) } },
            )
            FieldRow(
                label = stringResource(R.string.wizard_minecraft_whitelist),
                value = settings.minecraftJavaWhitelist,
                onValueChange = { names -> edit { it.copy(minecraftJavaWhitelist = names) } },
                placeholder = "dana, alex",
            )
            FieldRow(
                label = stringResource(R.string.wizard_minecraft_operators),
                value = settings.minecraftJavaOperators,
                onValueChange = { names -> edit { it.copy(minecraftJavaOperators = names) } },
                showDivider = showDivider || settings.minecraftJavaWhitelist.isBlank(),
                placeholder = "dana",
            )
            if (settings.minecraftJavaWhitelist.isBlank()) {
                InfoRow(stringResource(R.string.wizard_minecraft_no_whitelist), showDivider)
            }
        }

        ServiceID.MINECRAFT_BEDROCK -> {
            FieldRow(
                label = stringResource(R.string.wizard_minecraft_version),
                value = settings.minecraftBedrockVersion,
                onValueChange = { version -> edit { it.copy(minecraftBedrockVersion = version) } },
                placeholder = "1.21.44",
            )
            PortFieldRow(
                label = stringResource(R.string.wizard_bedrock_port),
                value = settings.minecraftBedrockPort,
                onValue = { port -> edit { it.copy(minecraftBedrockPort = port) } },
            )
            InfoRow(stringResource(R.string.wizard_bedrock_arm), showDivider)
        }

        ServiceID.HOME_ASSISTANT -> {
            FieldRow(
                label = stringResource(R.string.wizard_ha_stick),
                value = settings.homeAssistantUSBDevice,
                onValueChange = { path -> edit { it.copy(homeAssistantUSBDevice = path) } },
                placeholder = "/dev/serial/by-id/usb-...",
            )
            if (model.canListSerialDevices) {
                SerialPicker(model, settings.homeAssistantUSBDevice) { path ->
                    edit { it.copy(homeAssistantUSBDevice = path) }
                }
            }
            InfoRow(stringResource(R.string.wizard_ha_stick_note), showDivider)
        }

        else -> Unit
    }
}

/** One VPN protocol's own port fields */
@Composable
fun ColumnScope.VPNProtocolAdvancedFields(
    model: ConfiguratorViewModel,
    form: ConfiguratorForm,
    protocol: ServiceID,
    showDivider: Boolean,
) {
    val settings = form.serviceSettings
    fun edit(change: (ServiceSettings) -> ServiceSettings) =
        model.update { it.copy(serviceSettings = change(it.serviceSettings)) }

    when (protocol) {
        ServiceID.WIREGUARD_VPN -> PortFieldRow(
            label = stringResource(R.string.wizard_vpn_port),
            value = settings.wireguardVPNPort,
            onValue = { port -> edit { it.copy(wireguardVPNPort = port) } },
            showDivider = showDivider,
        )
        ServiceID.AMNEZIA_WG -> PortFieldRow(
            label = stringResource(R.string.wizard_amnezia_port),
            value = settings.amneziaWGPort,
            onValue = { port -> edit { it.copy(amneziaWGPort = port) } },
            showDivider = showDivider,
        )
        ServiceID.SHADOWSOCKS -> PortFieldRow(
            label = stringResource(R.string.wizard_shadowsocks_port),
            value = settings.shadowsocksPort,
            onValue = { port -> edit { it.copy(shadowsocksPort = port) } },
            showDivider = showDivider,
        )
        ServiceID.XRAY_REALITY -> {
            PortFieldRow(
                label = stringResource(R.string.wizard_reality_port),
                value = settings.xrayRealityPort,
                onValue = { port -> edit { it.copy(xrayRealityPort = port) } },
            )
            FieldRow(
                label = stringResource(R.string.wizard_reality_sni),
                value = settings.xrayRealitySNI,
                onValueChange = { sni -> edit { it.copy(xrayRealitySNI = sni) } },
                placeholder = "www.apple.com",
                showDivider = showDivider,
            )
        }
        ServiceID.OPEN_VPN -> PortFieldRow(
            label = stringResource(R.string.wizard_openvpn_port),
            value = settings.openVPNPort,
            onValue = { port -> edit { it.copy(openVPNPort = port) } },
            showDivider = showDivider,
        )
        else -> Unit
    }
}

/** A number field over a typed setting */
@Composable
private fun ColumnScope.PortFieldRow(
    label: String,
    value: Int,
    onValue: (Int) -> Unit,
    showDivider: Boolean = true,
) {
    var typed by remember(label) { mutableStateOf(value.toString()) }
    FieldRow(
        label = label,
        value = typed,
        onValueChange = { text ->
            typed = text.filter { it.isDigit() }
            typed.toIntOrNull()?.let(onValue)
        },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        showDivider = showDivider,
    )
}

/** Which server the Java edition runs */
@Composable
private fun ColumnScope.FlavourRow(value: String, onChoose: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        ValueRow(
            title = stringResource(R.string.wizard_minecraft_type),
            value = value,
            onClick = { open = true },
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            for (flavour in listOf("PAPER", "VANILLA", "FABRIC", "FORGE")) {
                DropdownMenuItem(
                    text = { Text(flavour) },
                    onClick = { onChoose(flavour); open = false },
                )
            }
        }
    }
}

/** The sticks the server itself reports */
@Composable
private fun ColumnScope.SerialPicker(
    model: ConfiguratorViewModel,
    chosen: String,
    onPick: (String) -> Unit,
) {
    val listing by model.serialListing.collectAsState()
    when (val state = listing) {
        is ConfiguratorViewModel.SerialListing.Idle ->
            ActionRow(
                text = stringResource(R.string.wizard_ha_read_sticks),
                onClick = { model.loadSerialDevices() },
            )

        is ConfiguratorViewModel.SerialListing.Loading ->
            InfoRow(stringResource(R.string.wizard_ha_asking_server), true)

        is ConfiguratorViewModel.SerialListing.Loaded -> {
            state.devices.forEach { device ->
                ValueRow(
                    title = device.label,
                    subtitle = device.path,
                    value = if (device.path == chosen) "✓" else null,
                    onClick = { onPick(device.path) },
                )
            }
            if (state.devices.isEmpty()) {
                InfoRow(
                    stringResource(
                        if (state.directoryPresent) R.string.wizard_ha_no_stick
                        else R.string.wizard_ha_never_had_usb,
                    ),
                    true,
                )
            }
        }

        is ConfiguratorViewModel.SerialListing.Failed ->
            InfoRow(serialFailure(state.message), true)
    }
}

@Composable
private fun serialFailure(message: String): String = when (message) {
    ConfiguratorViewModel.NO_AGENT -> stringResource(R.string.wizard_ha_no_agent)
    ConfiguratorViewModel.FAILURE -> stringResource(R.string.wizard_ha_read_failed)
    else -> message
}

@Composable
private fun ColumnScope.InfoRow(text: String, showDivider: Boolean) {
    GroupedRow(showDivider = showDivider) {
        Text(
            text,
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.secondaryLabel,
        )
    }
}

/** The service's own name, from the catalog */
private fun displayName(id: ServiceID): String =
    ServiceRegistry.service(id)?.displayName ?: id.rawValue

private fun defaultHostname(id: ServiceID, domain: String, selected: Set<ServiceID>): String {
    val name = domain.ifBlank { "example.com" }
    val service = ServiceRegistry.service(id) ?: return name
    return service.webIngress(catalogContext(name, selected))?.hostname ?: name
}

private fun catalogContext(domain: String, selected: Set<ServiceID>): ServiceContext =
    ServiceContext(domain = domain.ifBlank { "example.com" }, sshUser = "",
                   settings = ServiceSettings(), installedServices = selected)

private fun mailHostname(domain: String): String = "mail.${domain.ifBlank { "example.com" }}"

private fun autheliaCandidates(form: ConfiguratorForm): List<ServiceID> =
    ServiceRegistry.services(form.services)
        .filter { it.id != ServiceID.AUTHELIA }
        .filter { it.id !in AutheliaService.NEVER_PROTECTED }
        .filter { it.webIngress(catalogContext(form.domain, form.services)) != null }
        .map { it.id }
