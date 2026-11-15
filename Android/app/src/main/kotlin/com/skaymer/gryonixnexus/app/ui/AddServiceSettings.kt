package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.configurator.ConfiguratorForm
import com.skaymer.gryonixnexus.app.configurator.ConfiguratorViewModel
import com.skaymer.gryonixnexus.app.configurator.ServiceQuestions
import com.skaymer.gryonixnexus.app.configurator.of
import com.skaymer.gryonixnexus.app.licensing.LicensePrompt
import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.catalog.ServiceHostnames
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** The settings of the services being added, before they install */
@Composable
fun ColumnScope.AddServiceSettings(model: ConfiguratorViewModel, deployment: Deployment, adding: Set<ServiceID>) {
    val form by model.form.collectAsState()
    val questions = AddServiceSetup.questions(deployment, adding)
    if (questions.isNotEmpty()) ServiceAnswersSection(model, form, questions)
    val withFields = adding.filter(AddServiceSetup::hasFields).sortedBy { it.rawValue }
    withFields.forEach { id ->
        GroupedSection(header = displayName(id)) {
            ServiceAdvancedFields(model, form, id, showDivider = false)
        }
    }
    if (questions.isEmpty() && withFields.isEmpty()) {
        GroupedSection {
            GroupedRow(showDivider = false) {
                Text(
                    stringResource(R.string.add_service_nothing_to_set),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
        }
    }
}

/** The install choice with the new services' settings above it */
@Composable
fun AddServiceInstallSheet(
    deployment: Deployment,
    services: List<ManagedService>,
    scripts: List<Artifact>,
    makeModel: () -> ConfiguratorViewModel?,
    onInstall: (Deployment) -> Unit,
    onCancel: () -> Unit,
) {
    val ids = services.map { it.id }.toSet()
    val model = remember(deployment.id, ids) {
        makeModel()?.apply { adopt(AddServiceSetup.form(deployment, ids), deployment) }
    }
    val form = model?.form?.collectAsState()?.value
    val settings = form?.serviceSettings ?: deployment.serviceSettings
    val answered = AddServiceSetup.questions(deployment, ids).all { ServiceQuestions.isAnswered(it, settings) }
    InstallMethodSheet(
        services = services,
        scripts = scripts,
        onDevice = { onInstall(deployment.copy(serviceSettings = settings)) },
        onCancel = onCancel,
        allowed = { DemoDeployments.isDemoID(deployment.id) || LicensePrompt.allow() },
        installEnabled = answered,
        settings = { model?.let { AddServiceSettings(it, deployment, ids) } },
    )
}

/** Questions and starting form of the settings step */
object AddServiceSetup {
    private val withOwnFields = setOf(
        ServiceID.VAULTWARDEN, ServiceID.FORGEJO, ServiceID.GITLAB, ServiceID.AUTHELIA, ServiceID.PIHOLE,
        ServiceID.MINECRAFT_JAVA, ServiceID.MINECRAFT_BEDROCK, ServiceID.HOME_ASSISTANT,
        ServiceID.SHAIRPORT_SYNC, ServiceID.UXPLAY, ServiceID.WIREGUARD_VPN, ServiceID.AMNEZIA_WG,
        ServiceID.SHADOWSOCKS, ServiceID.XRAY_REALITY,
    )

    fun hasFields(id: ServiceID): Boolean = ServiceHostnames.asksHostname(id) || id in withOwnFields

    /** Only questions this server has not answered yet */
    fun questions(deployment: Deployment, adding: Set<ServiceID>): List<ServiceQuestions.Question> =
        ServiceQuestions.unansweredOn(deployment, adding)

    /** A form of this server with the new services ticked */
    fun form(deployment: Deployment, adding: Set<ServiceID>): ConfiguratorForm =
        ConfiguratorForm.of(deployment).copy(services = deployment.services + adding)
}
