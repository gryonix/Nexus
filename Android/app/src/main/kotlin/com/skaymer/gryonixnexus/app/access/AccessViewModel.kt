package com.skaymer.gryonixnexus.app.access

import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.agentcontrol.AgentVaultOperations
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the access screen is showing for one server */
data class AccessState(
    val accounts: List<AccessAccount> = emptyList(),
    val isLoading: Boolean = true,
    val hasReport: Boolean = false,
    val justSaved: Boolean = false,
    val revealed: Set<String> = emptySet(),
    /** Where these values live — see [AccessSync] */
    val sync: AccessSync = AccessSync.LocalOnly,
) {
    val saysThereIsNoReport: Boolean get() = !isLoading && !hasReport

    val saysThereAreNoLogins: Boolean get() = !isLoading && hasReport && accounts.isEmpty()

    val saysThereIsNothing: Boolean get() = saysThereIsNoReport && accounts.isEmpty()
}

/** Where the values on this screen live */
sealed interface AccessSync {
    data object Synced : AccessSync

    data object LocalOnly : AccessSync

    data object SignedOut : AccessSync

    data object Unidentified : AccessSync

    /** Saved here, but the server could not be reached */
    data class Failed(val message: String) : AccessSync
}

class AccessViewModel(
    private val scope: CoroutineScope,
    private val reports: (Deployment) -> InstallReportStore,
    private val credentials: (Deployment) -> AccessCredentialStore,
    private val import: InstallReportImport? = null,
    private val vault: (suspend (Deployment) -> AgentVaultOperations?)? = null,
    /** This installation's id, stamped into what this device writes */
    private val deviceUID: () -> String = { "" },
    private val now: () -> Long = { System.currentTimeMillis() },
    private val release: suspend (Deployment) -> Unit = {},
) {
    private val _state = MutableStateFlow(AccessState())
    val state: StateFlow<AccessState> = _state.asStateFlow()

    private var job: Job? = null

    fun load(deployment: Deployment) {
        job?.cancel()
        _state.value = AccessState()
        job = scope.launch {
            if (import != null) {
                try {
                    import.importIfNeeded(deployment)
                } finally {
                    release(deployment)
                }
            }
            val stored = reports(deployment).load()
            val overrides = credentials(deployment).load()
            val cards = stored.flatMap { report ->
                AccessAccount.cards(
                    host = report.host,
                    sections = InstallReportParser.sections(report.text),
                    overrides = overrides,
                )
            }
            _state.value = AccessState(
                accounts = cards.map { it.markingLoaded() },
                isLoading = false,
                hasReport = stored.isNotEmpty(),
            )
            syncDown(deployment, cards)
        }
    }

    /** Folds the server's copy into the cards */
    private suspend fun syncDown(deployment: Deployment, cards: List<AccessAccount>) {
        val operations = vault?.invoke(deployment) ?: run {
            _state.value = _state.value.copy(sync = AccessSync.LocalOnly)
            return
        }
        try {
            val remote = operations.snapshot().entries
            _state.value = _state.value.copy(
                accounts = AccessVault.applying(remote, cards.map { it.markingLoaded() }),
                sync = AccessSync.Synced,
            )
        } catch (error: Throwable) {
            val outcome = failure(error)
            if (outcome == AccessSync.SignedOut) signOut(deployment) else {
                _state.value = _state.value.copy(sync = outcome)
            }
        } finally {
            release(deployment)
        }
    }

    private fun signOut(deployment: Deployment) {
        runCatching { credentials(deployment).delete() }
        runCatching { reports(deployment).delete() }
        _state.value = AccessState(
            accounts = emptyList(),
            isLoading = false,
            hasReport = false,
            sync = AccessSync.SignedOut,
        )
    }

    /** The marker, not the wording */
    private fun failure(error: Throwable): AccessSync {
        val text = (error as? AgentError)?.message ?: error.message.orEmpty()
        return when {
            SIGNED_OUT_MARKERS.any { text.contains(it) } -> AccessSync.SignedOut
            text.contains(UNIDENTIFIED_MARKER) -> AccessSync.Unidentified
            else -> AccessSync.Failed(text)
        }
    }

    val showsHost: Boolean
        get() = _state.value.accounts.map { it.host }.distinct().size > 1

    fun editLogin(id: String, value: String) = edit(id) { it.copy(login = value) }

    fun editPassword(id: String, value: String) = edit(id) { it.copy(password = value) }

    fun editToken(id: String, value: String) = edit(id) { it.copy(token = value) }

    /** Unlock one secret field */
    fun reveal(fieldID: String) {
        _state.value = _state.value.copy(revealed = _state.value.revealed + fieldID)
    }

    fun hide(fieldID: String) {
        _state.value = _state.value.copy(revealed = _state.value.revealed - fieldID)
    }

    fun save(deployment: Deployment) {
        scope.launch {
            val accounts = _state.value.accounts
            val overrides = accounts.mapNotNull { account ->
                account.override()?.let { account.id to it }
            }.toMap()
            credentials(deployment).save(overrides)
            _state.value = _state.value.copy(
                justSaved = true,
                accounts = accounts.map { it.markingLoaded() },
            )
            pushUp(deployment, accounts)
        }
    }

    private suspend fun pushUp(deployment: Deployment, accounts: List<AccessAccount>) {
        val operations = vault?.invoke(deployment) ?: return
        val outgoing = AccessVault.entriesToPush(accounts, now(), deviceUID())
        if (outgoing.isEmpty()) return
        try {
            operations.save(outgoing)
            _state.value = _state.value.copy(sync = AccessSync.Synced)
        } catch (error: Throwable) {
            val outcome = failure(error)
            _state.value = _state.value.copy(
                sync = if (outcome == AccessSync.SignedOut || outcome == AccessSync.Unidentified) {
                    AccessSync.Failed(error.message.orEmpty())
                } else {
                    outcome
                },
            )
        } finally {
            release(deployment)
        }
    }

    /** Forget the whole screen */
    fun reset() {
        job?.cancel()
        job = null
        _state.value = AccessState()
    }

    private companion object {
        val SIGNED_OUT_MARKERS = listOf("session_expired", "device_not_paired")

        const val UNIDENTIFIED_MARKER = "device_unidentified"
    }

    private fun edit(id: String, change: (AccessAccount) -> AccessAccount) {
        _state.value = _state.value.copy(
            accounts = _state.value.accounts.map { if (it.id == id) change(it) else it },
            justSaved = false,
        )
    }
}
