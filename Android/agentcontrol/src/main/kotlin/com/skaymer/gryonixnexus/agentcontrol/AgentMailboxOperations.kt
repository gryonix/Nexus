package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import com.skaymer.gryonixnexus.servercontrol.L10nOperations
import com.skaymer.gryonixnexus.servercontrol.Mailbox
import com.skaymer.gryonixnexus.servercontrol.MailboxManaging
import com.skaymer.gryonixnexus.servercontrol.ServerControlError

class AgentMailboxOperations(
    private val client: AgentClient,
    private val engineInstalled: Boolean,
    private val gate: AgentChannelGate? = null,
    private val language: AppLanguage = AppLanguage.EN,
) : MailboxManaging {
    override val isAvailable: Boolean get() = engineInstalled

    override suspend fun list(): List<Mailbox> {
        requireEngine()
        return mapping { client.listMailboxes().map(::mailbox) }
    }

    override suspend fun add(address: String, password: String) {
        validate(address)
        requirePassword(password)
        mapping { client.createMailbox(address, password) }
    }

    override suspend fun delete(address: String) {
        validate(address)
        mapping { client.deleteMailbox(address) }
    }

    override suspend fun setPassword(address: String, password: String) {
        validate(address)
        requirePassword(password)
        mapping { client.setMailboxPassword(address, password) }
    }

    // --------------------------------------------------------------- Helpers

    private suspend fun <T> mapping(body: suspend () -> T): T =
        agentFailure("mailboxes") { gate.gated(body) }

    private fun validate(address: String) {
        requireEngine()
        if (!CommandCatalog.DockerMailserver.isValidAddress(address)) {
            throw ServerControlError.NotConfigured(
                L10nOperations.mailboxInvalidAddress(language, address),
            )
        }
    }

    private fun requirePassword(password: String) {
        if (password.isEmpty()) {
            throw ServerControlError.NotConfigured(L10nOperations.mailboxPasswordEmpty(language))
        }
    }

    private fun requireEngine() {
        if (!isAvailable) {
            throw ServerControlError.NotConfigured(L10nOperations.mailboxesNotAvailable(language))
        }
    }

    companion object {
        /** The agent's row in the shape the screen already reads */
        internal fun mailbox(row: gryonixnexusd.v1.Mailbox) =
            Mailbox(row.address, row.detail.ifEmpty { null })
    }
}
