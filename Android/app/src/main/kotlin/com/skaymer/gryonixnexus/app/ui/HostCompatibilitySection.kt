package com.skaymer.gryonixnexus.app.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.agentcontrol.InstallFinding
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.catalog.ServiceRegistry

/** What the machine lacks for the chosen services */
@Composable
fun HostCompatibilitySection(findings: List<InstallFinding>) {
    if (findings.isEmpty()) return
    val footer = if (findings.any { it.isBlocking }) stringResource(R.string.host_check_footer) else null
    GroupedSection(header = stringResource(R.string.host_check_header), footer = footer) {
        findings.forEachIndexed { index, finding ->
            GroupedRow(showDivider = index < findings.lastIndex) {
                Text(
                    hostFindingText(finding),
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (finding.isBlocking) Gryonix.colors.danger else Gryonix.colors.warning,
                )
            }
        }
    }
}

/** A finding in the app's own words */
@Composable
private fun hostFindingText(finding: InstallFinding): String {
    val name = ServiceRegistry.service(finding.service)?.displayName ?: finding.service.rawValue
    val args = finding.args
    return when {
        finding.code == "needs_newer_os" && args.size >= 2 ->
            stringResource(R.string.host_check_needs_newer_os, name, args[1], args[0])
        finding.code == "package_unavailable" && args.size >= 2 ->
            stringResource(R.string.host_check_package_unavailable, name, args[0], args[1])
        finding.code == "reduced_on_older_os" && args.size >= 2 ->
            stringResource(R.string.host_check_reduced_on_older_os, name, args[0], args[1])
        finding.code == "no_sound_card" && finding.isBlocking -> stringResource(R.string.host_check_no_sound_card_blocked, name)
        finding.code == "no_sound_card" -> stringResource(R.string.host_check_no_sound_card_limited, name)
        else -> finding.message
    }
}
