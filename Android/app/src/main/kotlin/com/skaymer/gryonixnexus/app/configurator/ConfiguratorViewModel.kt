package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.app.secrets.AppIdentities
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.catalog.applyingHostnames
import com.skaymer.gryonixnexus.core.GeneratedBundle
import com.skaymer.gryonixnexus.core.ValidationError
import com.skaymer.gryonixnexus.recipe.MailRecipe
import com.skaymer.gryonixnexus.recipe.OpenPortRequirement
import com.skaymer.gryonixnexus.recipe.OpenPortsSummary
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import gryonixnexusd.v1.SerialDevice
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class ConfiguratorViewModel(
    private val fleet: FleetRepository,
    private val secrets: SecretStore,
    private val language: AppLanguage = AppLanguage.EN,
    /** Where a generated configuration is remembered — see [ConfiguratorHistory] */
    private val history: ConfiguratorHistory? = null,
    private val scope: CoroutineScope? = null,
    /** How the stick picker reaches the server's agent */
    private val agentClient: (suspend (Deployment) -> AgentClient?)? = null,
    private val releaseAgent: suspend (Deployment) -> Unit = {},
    private val onGenerated: suspend () -> Unit = {},
) {
    /** What the stick picker shows right now */
    sealed interface SerialListing {
        data object Idle : SerialListing
        data object Loading : SerialListing
        data class Loaded(
            val devices: List<SerialDevice>,
            val directoryPresent: Boolean,
        ) : SerialListing
        data class Failed(val message: String) : SerialListing
    }

    private val identities = AppIdentities(secrets)
    private val recorder = DeploymentRecorder(fleet, secrets)

    private val _form = MutableStateFlow(ConfiguratorForm())
    val form: StateFlow<ConfiguratorForm> = _form.asStateFlow()

    fun historyEntries(): List<ConfiguratorHistoryEntry> = history?.entries().orEmpty()

    fun deleteFromHistory(ids: Set<String>) = history?.delete(ids) ?: Unit

    /** Fills the form from a history entry */
    fun restore(entry: ConfiguratorHistoryEntry) {
        adopt(entry.toForm())
    }

    private val _bundle = MutableStateFlow<GeneratedBundle?>(null)
    val bundle: StateFlow<GeneratedBundle?> = _bundle.asStateFlow()

    private val _openPorts = MutableStateFlow<List<OpenPortRequirement>>(emptyList())
    val openPorts: StateFlow<List<OpenPortRequirement>> = _openPorts.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _savedDeployment = MutableStateFlow<Deployment?>(null)
    val savedDeployment: StateFlow<Deployment?> = _savedDeployment.asStateFlow()

    /** The password of the EXISTING account, per machine */
    private val existingUserPasswords = mutableMapOf<SSHHostID, String>()

    fun password(host: SSHHostID): String = existingUserPasswords[host].orEmpty()

    fun setPassword(host: SSHHostID, value: String) {
        existingUserPasswords[host] = value
        _error.value = null
    }

    /** The `authorized_keys` line this device would install */
    fun appPublicKey(): String? = runCatching { identities.publicKey(deploymentID()) }.getOrNull()

    fun adopt(form: ConfiguratorForm, server: Deployment? = null) {
        carriedID = null
        existingServer = server
        _serialListing.value = SerialListing.Idle
        update { form }
    }

    /** The server this run is re-configuring, when there is one */
    private var existingServer: Deployment? = null

    private val _serialListing = MutableStateFlow<SerialListing>(SerialListing.Idle)
    val serialListing: StateFlow<SerialListing> = _serialListing.asStateFlow()

    /** Whether the stick can be read off the machine */
    val canListSerialDevices: Boolean
        get() = scope != null && agentClient != null && existingServer?.usesAgent == true

    fun loadSerialDevices() {
        val server = existingServer ?: return
        val client = agentClient ?: return
        val runner = scope ?: return
        _serialListing.value = SerialListing.Loading
        runner.launch {
            val agent = client(server)
            if (agent == null) {
                _serialListing.value = SerialListing.Failed(NO_AGENT)
                return@launch
            }
            try {
                val answer = agent.listSerialDevices()
                _serialListing.value =
                    SerialListing.Loaded(answer.devices, answer.directory_present)
            } catch (error: Throwable) {
                _serialListing.value = SerialListing.Failed(error.message ?: FAILURE)
            } finally {
                releaseAgent(server)
            }
        }
    }

    /** Forget what the last generation produced, without touching the answers */
    fun discardBundle() {
        _bundle.value = null
        _openPorts.value = emptyList()
        _savedDeployment.value = null
        _error.value = null
    }

    fun update(transform: (ConfiguratorForm) -> ConfiguratorForm) {
        _form.value = transform(_form.value)
        _bundle.value = null
        _openPorts.value = emptyList()
        _savedDeployment.value = null
        _error.value = null
    }

    fun toggle(id: ServiceID) {
        val service = ServiceRegistry.service(id) ?: return
        update { form ->
            val picked = form.services
            val next = when {
                id in picked -> picked - id
                service.category.selection == ServiceCategory.Selection.EXCLUSIVE ->
                    picked - ServiceRegistry.ids(service.category) + id
                else -> picked + id
            }
            form.copy(services = next)
        }
    }

    fun installedServices(): Set<ServiceID> =
        ServiceRegistry.expanded(
            _form.value.services,
            _form.value.scope,
            _form.value.serviceSettings.modelBackend
        )

    private fun deploymentID(): String {
        val id = recorder.identify(_form.value, carriedID)
        carriedID = id
        return id
    }

    private var carriedID: String? = null

    fun useDemoAddressesIfLocked() {
        if (LicenseGate.unlocked) return
        val form = _form.value
        val local = form.isLocalOnly
        val demo = form.copy(
            publicIP = if (local) DEMO_LOCAL_IP else DEMO_PUBLIC_IP,
            domain = if (local) DEMO_LOCAL_IP else DEMO_DOMAIN,
            homeNetworkAddress = if (form.topology == Topology.VPS_RELAY_WITH_HOME_BACKEND) DEMO_LOCAL_IP else "",
            additionalDomains = emptyList(),
            reverseDNSHostname = "",
            serviceSettings = form.serviceSettings.applyingHostnames(emptyMap()).copy(vpnHostname = ""),
        )
        if (demo != form) _form.value = demo
    }

    fun generate() {
        useDemoAddressesIfLocked()
        val form = _form.value
        if (form.includeDashboardAccess && form.useExistingUser) {
            val missing = machines(form).filter { existingUserPasswords[it].isNullOrEmpty() }
            if (missing.isNotEmpty()) {
                _bundle.value = null
                _openPorts.value = emptyList()
                _savedDeployment.value = null
                _error.value = MISSING_PASSWORD
                return
            }
        }
        try {
            val id = deploymentID()
            val key = if (form.includeDashboardAccess) appPublicKey() else null
            val input = form.toInput(language, key)
            _bundle.value = MailRecipe().generate(input)
            _openPorts.value = OpenPortsSummary.entryHostPorts(input)
            _error.value = null
            history?.append(form)
            if (LicenseGate.unlocked) scope?.launch { onGenerated() }
            _savedDeployment.value = if (key != null) {
                recorder.record(
                    id = id,
                    form = form,
                    services = installedServices(),
                    passwords = if (form.useExistingUser) existingUserPasswords.toMap() else emptyMap(),
                )
            } else {
                null
            }
        } catch (failure: ValidationError) {
            _bundle.value = null
            _openPorts.value = emptyList()
            _savedDeployment.value = null
            _error.value = failure.message(language)
        }
    }

    private fun machines(form: ConfiguratorForm): List<SSHHostID> =
        if (form.topology == Topology.VPS_RELAY_WITH_HOME_BACKEND) {
            listOf(SSHHostID.VPS, SSHHostID.HOME)
        } else {
            listOf(SSHHostID.VPS)
        }

    companion object {
        const val DEMO_DOMAIN = "example.net"
        const val DEMO_PUBLIC_IP = "203.0.113.10"
        const val DEMO_LOCAL_IP = "192.168.1.50"
        private const val MISSING_PASSWORD =
            "Enter the password of the existing account — the app signs in with it, " +
                "and it is stored on this device only."

        const val NO_AGENT = "no_agent"
        const val FAILURE = "failure"
    }
}
