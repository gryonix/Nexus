package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceCommand

class UninstallOperations(
    private val runner: SSHCommandRunner,
    private val deployment: Deployment,
) {
    sealed class Event {
        data class HostStarted(val host: SSHHostID) : Event()
        data class Output(val text: String) : Event()
        data class HostFinished(val host: SSHHostID) : Event()
    }

    val hosts: List<SSHHostID> get() = deployment.teardownOrder.map { it.sshHost }

    /** Cleans every host of the deployment */
    suspend fun fullCleanup(purge: PurgeOptions, onEvent: (Event) -> Unit) {
        for (host in hosts) {
            onEvent(Event.HostStarted(host))
            val command = CommandCatalog.Uninstall.fullCleanup(purge)
            val accumulated = StringBuilder()
            val id = DetachedJobs.jobID(DetachedJobs.Kind.UNINSTALL, "all", System.currentTimeMillis() / 1000)
            try {
                runner.run(
                    DetachedJobs.startCommand(command, id), host,
                    deployment.timeouts.duration(ServiceCommand.TimeoutClass.QUICK),
                )
                DetachedJobs.follow(
                    runner, host, id, deployment.timeouts.duration(ServiceCommand.TimeoutClass.LONG),
                ) { text ->
                    accumulated.append(text)
                    onEvent(Event.Output(text))
                }
            } catch (cancelled: kotlin.coroutines.cancellation.CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                if (!ANSIStripper.strip(accumulated.toString()).contains(CommandCatalog.Uninstall.DONE_MARKER)) throw failure
            }
            val output = ANSIStripper.strip(accumulated.toString())
            if (!output.contains(CommandCatalog.Uninstall.DONE_MARKER)) {
                throw ServerControlError.commandFailure(command, null, OutputTail.tail(output))
            }
            onEvent(Event.HostFinished(host))
        }
    }
}
