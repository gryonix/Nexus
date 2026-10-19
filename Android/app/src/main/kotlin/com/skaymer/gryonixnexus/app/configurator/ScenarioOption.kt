package com.skaymer.gryonixnexus.app.configurator

import androidx.annotation.StringRes
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.Topology

data class ScenarioOption(
    val id: String,
    @StringRes val title: Int,
    @StringRes val subtitle: Int,
    val icon: ScenarioIcon,
    val topology: Topology,
    val scope: DeploymentScope,
) {
    companion object {
        val all: List<ScenarioOption> = listOf(
            ScenarioOption(
                id = "single",
                title = R.string.scenario_single_title,
                subtitle = R.string.scenario_single_subtitle,
                icon = ScenarioIcon.SERVER,
                topology = Topology.SINGLE_HOST,
                scope = DeploymentScope.PUBLIC_INTERNET,
            ),
            ScenarioOption(
                id = "relay",
                title = R.string.scenario_relay_title,
                subtitle = R.string.scenario_relay_subtitle,
                icon = ScenarioIcon.RELAY,
                topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
                scope = DeploymentScope.PUBLIC_INTERNET,
            ),
            ScenarioOption(
                id = "localOnly",
                title = R.string.scenario_local_only_title,
                subtitle = R.string.scenario_local_only_subtitle,
                icon = ScenarioIcon.HOUSE,
                topology = Topology.SINGLE_HOST,
                scope = DeploymentScope.LOCAL_ONLY,
            ),
            ScenarioOption(
                id = "cloudflareTunnel",
                title = R.string.scenario_cloudflare_tunnel_title,
                subtitle = R.string.scenario_cloudflare_tunnel_subtitle,
                icon = ScenarioIcon.CLOUD,
                topology = Topology.SINGLE_HOST,
                scope = DeploymentScope.CLOUDFLARE_TUNNEL,
            ),
            ScenarioOption(
                id = "dynamicDNS",
                title = R.string.scenario_dynamic_dns_title,
                subtitle = R.string.scenario_dynamic_dns_subtitle,
                icon = ScenarioIcon.REFRESH,
                topology = Topology.SINGLE_HOST,
                scope = DeploymentScope.DYNAMIC_DNS,
            ),
            ScenarioOption(
                id = "meshOnly",
                title = R.string.scenario_mesh_only_title,
                subtitle = R.string.scenario_mesh_only_subtitle,
                icon = ScenarioIcon.MESH,
                topology = Topology.SINGLE_HOST,
                scope = DeploymentScope.MESH_ONLY,
            ),
        )
    }
}

enum class ScenarioIcon { SERVER, RELAY, HOUSE, CLOUD, REFRESH, MESH }
