package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.setValue
import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.servers.AdoptResult
import com.skaymer.gryonixnexus.app.servers.AgentAdoption
import com.skaymer.gryonixnexus.app.servers.ServerTint
import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HomePathChoice
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.MetricsIndicatorStyle
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import java.util.UUID

/** What the add-server screen has collected so far */
class AddHostForm(val id: String = UUID.randomUUID().toString().uppercase()) {
    enum class Step { CONNECTION, DETAILS }

    var step by mutableStateOf(Step.CONNECTION)
    var topology by mutableStateOf(Topology.SINGLE_HOST)
    var scope by mutableStateOf(DeploymentScope.PUBLIC_INTERNET)
    var host by mutableStateOf("")
    var port by mutableStateOf("22")
    var user by mutableStateOf("root")
    var usesPassword by mutableStateOf(false)
    var password by mutableStateOf("")
    var homeWGAddress by mutableStateOf("10.8.0.2")
    var homeLANAddress by mutableStateOf("")
    var homeUser by mutableStateOf("")
    var homePath by mutableStateOf(HomePathChoice.AUTOMATIC)
    var wgInterface by mutableStateOf("wg0")
    var homePassword by mutableStateOf("")
    var name by mutableStateOf("")
    var domain by mutableStateOf("")
    var tags by mutableStateOf(listOf<String>())
    var indicator by mutableStateOf<MetricsIndicatorStyle?>(null)
    var tint by mutableStateOf<ServerTint?>(null)
    var icon by mutableStateOf<String?>(null)
    private var services by mutableStateOf(setOf<ServiceID>())
    private var aliases by mutableStateOf(listOf<String>())
    private var usesAgent by mutableStateOf(false)

    private val relay get() = topology == Topology.VPS_RELAY_WITH_HOME_BACKEND

    private val endpoint
        get() = HostEndpoint(host = host.trim(), port = port.toIntOrNull() ?: 0, user = user.trim())

    val canConnect: Boolean
        get() = endpoint.host.isNotEmpty() && endpoint.user.isNotEmpty() && endpoint.port in 1..65535 &&
            (!usesPassword || password.isNotEmpty())

    val canSave: Boolean
        get() = canConnect && name.isNotBlank() && (!usesPassword || !relay || homePassword.isNotEmpty())

    fun deployment(): Deployment = Deployment(
        id = id,
        name = name.trim().ifEmpty { host.trim() },
        topology = topology,
        domain = domain.trim().lowercase(),
        additionalDomains = aliases,
        entry = endpoint,
        homeWGAddress = homeWGAddress.trim().takeIf { relay },
        homeUser = homeUser.trim().takeIf { relay && it.isNotEmpty() },
        wgInterface = wgInterface.trim().ifEmpty { "wg0" },
        services = services,
        tags = tags,
        metricsIndicatorStyle = indicator,
        usesPasswordAuth = usesPassword,
        usesAgent = usesAgent,
        tintName = tint?.raw,
        iconSymbol = icon,
        scope = scope,
    )

    /** Keeps the typed passwords where the sessions read them */
    fun stage(store: SecretStore) {
        val secrets = DeploymentSecrets(store, id)
        if (relay) secrets.setHomeAddress(homeLANAddress)
        if (relay) secrets.setHomePath(homePath)
        if (!usesPassword) return
        if (password.isNotEmpty()) secrets.setPassword(password, SSHHostID.VPS)
        if (relay && homePassword.isNotEmpty()) secrets.setPassword(homePassword, SSHHostID.HOME)
    }

    /** Takes the agent's answer about the machine */
    fun adopted(result: AdoptResult) {
        services = result.services
        usesAgent = true
        if (name.isBlank()) name = AgentAdoption.name(result.hostname, "")
        if (domain.isBlank()) domain = AgentAdoption.domain(result.domains)
        aliases = result.domains.drop(1)
    }

    fun nameFromHost() {
        if (name.isBlank()) name = host.trim()
    }

    companion object {
        val Saver: Saver<AddHostForm, List<Any?>> = Saver(
            save = { form ->
                listOf(form.id, form.step.name, form.topology.name, form.scope.name, form.host, form.port, form.user,
                    form.usesPassword, form.homeWGAddress, form.wgInterface, form.name, form.domain,
                    form.tags.joinToString("\n"), form.indicator?.name, form.tint?.name, form.icon, form.homeLANAddress, form.homeUser, form.homePath.name)
            },
            restore = { saved -> restored(saved) },
        )

        private fun restored(saved: List<Any?>): AddHostForm = AddHostForm(saved[0] as String).apply {
            step = Step.valueOf(saved[1] as String)
            topology = Topology.valueOf(saved[2] as String)
            scope = DeploymentScope.valueOf(saved[3] as String)
            host = saved[4] as String
            port = saved[5] as String
            user = saved[6] as String
            usesPassword = saved[7] as Boolean
            homeWGAddress = saved[8] as String
            wgInterface = saved[9] as String
            name = saved[10] as String
            domain = saved[11] as String
            tags = (saved[12] as String).split("\n").filter { it.isNotEmpty() }
            indicator = (saved[13] as String?)?.let(MetricsIndicatorStyle::valueOf)
            tint = (saved[14] as String?)?.let(ServerTint::valueOf)
            icon = saved.getOrNull(15) as String?
            homeLANAddress = saved.getOrNull(16) as String? ?: ""
            homeUser = saved.getOrNull(17) as String? ?: ""
            homePath = (saved.getOrNull(18) as String?)?.let(HomePathChoice::valueOf) ?: HomePathChoice.AUTOMATIC
        }
    }
}
