package com.skaymer.gryonixnexus.app.mail

import androidx.annotation.StringRes
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.Mailbox
import com.skaymer.gryonixnexus.servercontrol.MailboxManaging
import java.security.SecureRandom
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the mailbox screen is showing about one server */
data class MailboxesState(
    val mailboxes: List<Mailbox> = emptyList(),
    val isLoading: Boolean = false,
    /** Whether the SERVER has answered about its mailboxes at all */
    val hasAnswered: Boolean = false,
    val errorMessage: String? = null,
    val isWorking: Boolean = false,
) {
    val saysThereAreNone: Boolean
        get() = hasAnswered && errorMessage == null && !isLoading && mailboxes.isEmpty()
}

/** The mailboxes of the docker-mailserver engine */
class MailboxesViewModel(
    private val scope: CoroutineScope,
    private val mailboxes: suspend (Deployment) -> MailboxManaging,
    private val release: suspend (Deployment) -> Unit = {},
    private val savePassword: suspend (Deployment, String, String) -> Unit = { _, _, _ -> },
) {
    private val _state = MutableStateFlow(MailboxesState())
    val state: StateFlow<MailboxesState> = _state.asStateFlow()

    fun load(deployment: Deployment) {
        scope.launch {
            _state.value = _state.value.copy(isLoading = true, errorMessage = null)
            read(deployment)
        }
    }

    fun add(deployment: Deployment, address: String, password: String) =
        act(deployment, R.string.notice_mailbox_add, address, password) { it.add(address, password) }

    fun delete(deployment: Deployment, address: String) =
        act(deployment, R.string.notice_mailbox_remove) { it.delete(address) }

    fun setPassword(deployment: Deployment, address: String, password: String) =
        act(deployment, R.string.notice_mailbox_password, address, password) { it.setPassword(address, password) }

    fun reset() {
        _state.value = MailboxesState()
    }

    private fun act(deployment: Deployment, @StringRes title: Int, address: String? = null,
                    password: String? = null, body: suspend (MailboxManaging) -> Unit) {
        if (_state.value.isWorking) return
        _state.value = _state.value.copy(isWorking = true, errorMessage = null)
        scope.launch {
            _state.value = _state.value.copy(isWorking = true, errorMessage = null)
            val notice = OperationNotices.start(title, server = deployment.name, text = address.orEmpty())
            try {
                body(mailboxes(deployment))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                _state.value = _state.value.copy(isWorking = false, errorMessage = reason(failure))
                notice.finish("", reason(failure))
                return@launch
            }
            notice.finish(OperationNotices.text(R.string.notice_done))
            var vaultFailure = false
            if (address != null && password != null && deployment.usesAgent) {
                try {
                    savePassword(deployment, address, password)
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (_: Exception) {
                    vaultFailure = true
                }
            }
            read(deployment)
            if (vaultFailure) _state.value = _state.value.copy(
                errorMessage = VAULT_FAILURE,
            )
        }
    }

    private suspend fun read(deployment: Deployment) {
        try {
            val listing = mailboxes(deployment).list()
            _state.value = MailboxesState(
                mailboxes = listing,
                hasAnswered = true,
            )
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            release(deployment)
            _state.value = _state.value.copy(
                isLoading = false,
                isWorking = false,
                hasAnswered = true,
                errorMessage = reason(failure),
            )
        }
    }

    private fun reason(failure: Exception): String =
        failure.message ?: failure::class.simpleName.orEmpty()

    companion object {
        const val VAULT_FAILURE = "mailbox_vault_failure"
        fun hasEngine(deployment: Deployment): Boolean =
            ServiceID.DOCKER_MAILSERVER in deployment.services

        fun domains(deployment: Deployment): List<String> =
            listOf(deployment.domain) + deployment.additionalDomains

        /** Shortest password the server's own wrapper accepts */
        const val MINIMUM_PASSWORD_LENGTH = 8

        fun canCreate(address: String, password: String): Boolean =
            password.length >= MINIMUM_PASSWORD_LENGTH &&
                CommandCatalog.DockerMailserver.isValidAddress(address)

        fun canChangePassword(password: String): Boolean =
            password.length >= MINIMUM_PASSWORD_LENGTH
    }
}

object MailboxPassword {
    private const val ALPHABET = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    private val random = SecureRandom()

    fun generate(length: Int = 20): String =
        (0 until length).map { ALPHABET[random.nextInt(ALPHABET.length)] }.joinToString("")
}
