package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.agentclient.AgentRefusal
import com.skaymer.gryonixnexus.agentclient.AgentRefusals
import com.skaymer.gryonixnexus.app.ui.design.Gryonix

/** The advice text of a reason, or null */
internal fun refusalAdviceText(reason: String): Int? = when (reason) {
    "install.machine_not_at_home" -> R.string.refusal_machine_not_at_home
    "install.incompatible" -> R.string.refusal_incompatible
    "install.hub_has_player" -> R.string.refusal_hub_has_player
    "install.player_in_hub" -> R.string.refusal_player_in_hub
    "install.needs_home_assistant" -> R.string.refusal_needs_home_assistant
    "install.no_reverse_proxy" -> R.string.refusal_no_reverse_proxy
    "install.zigbee_no_stick", "install.stick_missing" -> R.string.refusal_stick
    "install.site_name_taken" -> R.string.refusal_site_name_taken
    "install.already_running" -> R.string.refusal_already_running
    "install.ports_in_use" -> R.string.refusal_ports_in_use
    "install.docker_unavailable", "host.docker_unavailable" -> R.string.refusal_docker_unavailable
    else -> refusalAdviceOutsideInstall(reason)
}

/** Advice texts for refusals of a running server */
private fun refusalAdviceOutsideInstall(reason: String): Int? = when (reason) {
    "security.not_installed", "mesh.not_installed", "models.no_engine", "audio.hub_not_installed" ->
        R.string.refusal_install_first
    "host.needs_repair" -> R.string.refusal_needs_repair
    "vpn.no_panel", "vpn.protocol_not_installed" -> R.string.refusal_vpn_install_first
    "vpn.panel_not_running", "vpn.login_refused" -> R.string.refusal_vpn_panel
    "jobs.cannot_stop" -> R.string.refusal_cannot_stop
    "containers.backup_required" -> R.string.refusal_backup_required
    "containers.nothing_to_archive" -> R.string.refusal_nothing_to_archive
    "sites.caddy_refused" -> R.string.refusal_caddy_refused
    "audio.hub_not_answering" -> R.string.refusal_hub_not_answering
    "firewall.rules_refused" -> R.string.refusal_firewall_refused
    "move.no_space" -> R.string.refusal_move_no_space
    "backup.unreadable" -> R.string.refusal_backup_unreadable
    "security.ssh_unchanged" -> R.string.refusal_ssh_unchanged
    else -> null
}

/** What a reason's advice names */
internal sealed interface RefusalAdviceValue {
    data class Words(val text: String) : RefusalAdviceValue
    data class Screen(val name: Int) : RefusalAdviceValue
    data object FirstArgument : RefusalAdviceValue
}

/** The value an advice text takes, or null */
internal fun refusalAdviceValue(reason: String): RefusalAdviceValue? = when (reason) {
    "install.machine_not_at_home" -> RefusalAdviceValue.Screen(R.string.wizard_machine_at_home)
    "install.hub_has_player" -> RefusalAdviceValue.FirstArgument
    "install.docker_unavailable", "host.docker_unavailable", "host.needs_repair", "firewall.rules_refused" ->
        RefusalAdviceValue.Screen(R.string.repair_server)
    "security.not_installed" -> RefusalAdviceValue.Words("CrowdSec")
    "mesh.not_installed" -> RefusalAdviceValue.Words("Headscale")
    "models.no_engine" -> RefusalAdviceValue.Words("Ollama")
    "audio.hub_not_installed" -> RefusalAdviceValue.Words("Audio hub (odio)")
    else -> null
}

/** Advice for one refusal, or null when there is none */
@Composable
private fun advice(refusal: AgentRefusal): String? {
    val text = refusalAdviceText(refusal.reason) ?: return null
    return when (val value = refusalAdviceValue(refusal.reason)) {
        null -> stringResource(text)
        is RefusalAdviceValue.Words -> stringResource(text, value.text)
        is RefusalAdviceValue.Screen -> stringResource(text, stringResource(value.name))
        RefusalAdviceValue.FirstArgument -> stringResource(text, refusal.args.firstOrNull().orEmpty())
    }
}

/** The advice under a failed run, when there is one */
@Composable
fun RefusalAdvice(error: String?) {
    val refusal = error?.let { AgentRefusals.find(it) } ?: return
    val text = advice(refusal) ?: return
    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(stringResource(R.string.refusal_what_to_do), fontWeight = FontWeight.SemiBold, color = Gryonix.colors.label)
        Text(text, style = MaterialTheme.typography.bodyMedium, color = Gryonix.colors.secondaryLabel)
    }
}
