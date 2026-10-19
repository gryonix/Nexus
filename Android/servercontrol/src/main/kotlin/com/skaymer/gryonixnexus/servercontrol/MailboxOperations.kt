package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.ServiceCommand
import com.skaymer.gryonixnexus.catalog.ServiceID
import kotlin.time.Duration

interface MailboxManaging {
    val isAvailable: Boolean

    suspend fun list(): List<Mailbox>
    suspend fun add(address: String, password: String)
    suspend fun delete(address: String)
    suspend fun setPassword(address: String, password: String)
}

/** Which implementation a deployment's mailbox screen goes through */
object MailboxRouting {
    fun route(
        usesAgent: Boolean,
        agentTransportAvailable: Boolean,
        hasEngine: Boolean,
    ): ServiceControlRoute {
        if (!hasEngine) return ServiceControlRoute.SSH
        return ServiceControlRouting.route(usesAgent, agentTransportAvailable)
    }
}

/** Mailbox management for the docker-mailserver engine */
class MailboxOperations(
    private val runner: SSHCommandRunner,
    private val deployment: Deployment,
    private val language: AppLanguage = AppLanguage.EN,
) : MailboxManaging {
    /** The machine the mail engine runs on */
    private val host: SSHHostID get() = deployment.hostRunning(ServiceID.DOCKER_MAILSERVER)

    private fun timeout(timeoutClass: ServiceCommand.TimeoutClass): Duration =
        deployment.timeouts.duration(timeoutClass)

    override val isAvailable: Boolean
        get() = deployment.services.contains(ServiceID.DOCKER_MAILSERVER)

    // --------------------------------------------------------------- Reading

    override suspend fun list(): List<Mailbox> {
        requireEngine()
        val command = CommandCatalog.DockerMailserver.LIST_MAILBOXES
        val result = runner.run(command, host, timeout(ServiceCommand.TimeoutClass.QUICK))
        if (!result.succeeded) {
            throw ServerControlError.commandFailure(
                command,
                result.exitCode,
                readable(result.stderr),
            )
        }
        return MailboxListParser.parse(result.stdout)
    }

    // --------------------------------------------------------------- Writing

    /** Creates a mailbox */
    override suspend fun add(address: String, password: String) {
        validate(address)
        requirePassword(password)
        mutate(
            CommandCatalog.DockerMailserver.addMailbox(address),
            label = "add mailbox",
            password = password,
            timeout = timeout(ServiceCommand.TimeoutClass.RESTART),
        )
    }

    /** Removes a mailbox and everything in it */
    override suspend fun delete(address: String) {
        validate(address)
        mutate(
            CommandCatalog.DockerMailserver.deleteMailbox(address),
            label = "delete mailbox",
            password = null,
            timeout = timeout(ServiceCommand.TimeoutClass.LONG),
        )
    }

    override suspend fun setPassword(address: String, password: String) {
        validate(address)
        requirePassword(password)
        mutate(
            CommandCatalog.DockerMailserver.setMailboxPassword(address),
            label = "change mailbox password",
            password = password,
            timeout = timeout(ServiceCommand.TimeoutClass.RESTART),
        )
    }

    // --------------------------------------------------------------- Helpers

    private suspend fun mutate(
        command: String,
        label: String,
        password: String?,
        timeout: Duration,
    ) {
        val result = if (password != null) {
            runner.run(command, password, host, timeout)
        } else {
            runner.run(command, host, timeout)
        }
        val stderr = readable(redacting(password, result.stderr))
        if (!result.succeeded) {
            throw ServerControlError.commandFailure(label, result.exitCode, stderr)
        }
        if (!result.stdout.contains(CommandCatalog.DockerMailserver.MAILBOX_DONE_MARKER)) {
            throw ServerControlError.CommandFailed(
                label,
                result.exitCode,
                stderr.ifEmpty { OutputTail.tail(readable(redacting(password, result.stdout))) },
            )
        }
    }

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
        /** Makes an engine message fit to be shown as-is */
        internal fun readable(text: String): String = ANSIStripper.strip(text).trim()

        internal fun redacting(password: String?, text: String): String {
            if (password.isNullOrEmpty() || !text.contains(password)) return text
            return text.replace(password, "***")
        }
    }
}
