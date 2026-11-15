package com.skaymer.gryonixnexus.app.servers.demo

import gryonixnexusd.v1.AgentUpdateStatus
import gryonixnexusd.v1.CreateTransferResponse
import gryonixnexusd.v1.DeletePreRestoreCopyRequest
import gryonixnexusd.v1.DiscardMoveTransferResponse
import gryonixnexusd.v1.ListPreRestoreCopiesRequest
import gryonixnexusd.v1.PrepareMoveReceiveResponse
import gryonixnexusd.v1.PrepareMoveSendResponse
import gryonixnexusd.v1.PreRestoreCopy
import gryonixnexusd.v1.PreRestoreCopyList
import gryonixnexusd.v1.RefreshCertificatesResponse
import gryonixnexusd.v1.RemoveAgentResponse
import gryonixnexusd.v1.ServiceUpstreamProbe
import gryonixnexusd.v1.ServiceUpstreamState
import gryonixnexusd.v1.SetAgentAutoUpdateRequest
import gryonixnexusd.v1.SetServiceUpstreamRequest
import gryonixnexusd.v1.StorageTaskResult
import okio.ByteString.Companion.toByteString
import java.util.UUID

/** Certificates, the agent switch, restore copies, moves and storage */
object DemoAgentLeftovers {
    fun answer(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Install/RefreshCertificates" -> RefreshCertificatesResponse(reloaded = true).demoPayload()
        "/gryonixnexusd.v1.AgentUpdate/SetAgentAutoUpdate" -> {
            val on = SetAgentAutoUpdateRequest.ADAPTER.decode(request).enabled
            DemoAgentState.memory(machine) { it.agentAutoUpdate = on }
            AgentUpdateStatus(installed_version = DemoAgentOffer.installedVersion, auto_update = on).demoPayload()
        }
        "/gryonixnexusd.v1.AgentUpdate/RemoveAgent" -> RemoveAgentResponse(scheduled = true).demoPayload()
        "/gryonixnexusd.v1.Storage/RunStorageTask" -> StorageTaskResult(exit_code = 0, output = "done (demo)").demoPayload()
        "/gryonixnexusd.v1.Pairing/CreateTransfer" -> CreateTransferResponse(
            transfer_id = UUID.randomUUID().toString(),
            private_key_seed = ByteArray(32) { 7 }.toByteString(),
            expires_at = System.currentTimeMillis() + 600_000,
        ).demoPayload()
        else -> restoreOrMove(path, request, machine)
    }

    private fun restoreOrMove(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Restore/ListPreRestoreCopies" ->
            copies(ListPreRestoreCopiesRequest.ADAPTER.decode(request).service_id, machine).demoPayload()
        "/gryonixnexusd.v1.Restore/DeletePreRestoreCopy" -> {
            val gone = DeletePreRestoreCopyRequest.ADAPTER.decode(request).path
            DemoAgentState.memory(machine) { it.deletedCopies.add(gone) }
            copies("", machine).demoPayload()
        }
        "/gryonixnexusd.v1.Move/SetServiceUpstream" -> {
            val asked = SetServiceUpstreamRequest.ADAPTER.decode(request)
            ServiceUpstreamState(
                current = if (asked.remote_address.isEmpty()) "local" else "remote",
                remote_address = asked.remote_address,
                changed = !asked.dry_run,
            ).demoPayload()
        }
        "/gryonixnexusd.v1.Move/ProbeServiceUpstream" -> ServiceUpstreamProbe(answered = true, status = 200).demoPayload()
        "/gryonixnexusd.v1.Move/PrepareMoveSend" -> PrepareMoveSendResponse(public_key = DEMO_KEY).demoPayload()
        "/gryonixnexusd.v1.Move/PrepareMoveReceive" ->
            PrepareMoveReceiveResponse(authorized_key_line = DEMO_KEY, free_bytes = 41_000_000_000).demoPayload()
        "/gryonixnexusd.v1.Move/DiscardMoveTransfer" -> DiscardMoveTransferResponse().demoPayload()
        else -> null
    }

    /** One copy per service, until deleted */
    private fun copies(serviceID: String, machine: DemoAgentMachine): PreRestoreCopyList {
        val deleted = DemoAgentState.memory(machine) { it.deletedCopies.toSet() }
        val services = if (serviceID.isEmpty()) machine.containers else listOf(serviceID)
        val threeDaysAgo = System.currentTimeMillis() / 1000 - 3 * 86_400
        return PreRestoreCopyList(
            copies = services.map {
                PreRestoreCopy(
                    service_id = it, path = "/opt/$it.before-restore", size_bytes = 182_000_000,
                    size_known = true, moved_aside_unix = threeDaysAgo,
                )
            }.filter { it.path !in deleted },
        )
    }

    private const val DEMO_KEY = "ssh-ed25519 AAAADEMO demo"
}
