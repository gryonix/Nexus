package com.skaymer.gryonixnexus.app.servers.demo

import gryonixnexusd.v1.CreateMailboxRequest
import gryonixnexusd.v1.DeleteMailboxRequest
import gryonixnexusd.v1.DeleteModFileRequest
import gryonixnexusd.v1.DeleteModelRequest
import gryonixnexusd.v1.DkimRecord
import gryonixnexusd.v1.DkimRecordList
import gryonixnexusd.v1.GetInstallPlanRequest
import gryonixnexusd.v1.ListModFilesRequest
import gryonixnexusd.v1.Mailbox
import gryonixnexusd.v1.MailboxList
import gryonixnexusd.v1.ModFile
import gryonixnexusd.v1.ModFileList
import gryonixnexusd.v1.ModProject
import gryonixnexusd.v1.ModSearchResult
import gryonixnexusd.v1.ModSlot
import gryonixnexusd.v1.ModVersion
import gryonixnexusd.v1.ModVersionList
import gryonixnexusd.v1.Model
import gryonixnexusd.v1.ModelList
import gryonixnexusd.v1.ProvisionHostResponse
import gryonixnexusd.v1.StartInstallPlanRequest
import gryonixnexusd.v1.UploadModFileRequest
import gryonixnexusd.v1.VaultwardenTwoFactor

/** Mail, DKIM, install plans, mods and models */
object DemoAgentServices {
    fun answer(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Mail/ListMailboxes", "/gryonixnexusd.v1.Mail/SetMailboxPassword" ->
            mailboxes(machine).demoPayload()
        "/gryonixnexusd.v1.Mail/CreateMailbox" -> {
            DemoFleetState.addMailbox(CreateMailboxRequest.ADAPTER.decode(request).address, machine)
            mailboxes(machine).demoPayload()
        }
        "/gryonixnexusd.v1.Mail/DeleteMailbox" -> {
            DemoFleetState.removeMailbox(DeleteMailboxRequest.ADAPTER.decode(request).address, machine)
            mailboxes(machine).demoPayload()
        }
        "/gryonixnexusd.v1.Dkim/GetDkimRecords" -> dkim(machine).demoPayload()
        "/gryonixnexusd.v1.Install/ProvisionHost" -> ProvisionHostResponse(
            written = listOf("/etc/caddy/Caddyfile", "/opt/gryonixnexus/compose"),
            control_user = machine.deployment.dashboardConfig.sshUser,
        ).demoPayload()
        "/gryonixnexusd.v1.Install/StartInstallPlan" -> {
            val asked = StartInstallPlanRequest.ADAPTER.decode(request)
            val ids = asked.services.map { it.service_id }
            ids.forEach { DemoFleetState.install(it, machine) }
            DemoInstallPlans.start(ids, asked.purpose).demoPayload()
        }
        "/gryonixnexusd.v1.Install/GetInstallPlan" ->
            DemoInstallPlans.get(GetInstallPlanRequest.ADAPTER.decode(request).plan_id).demoPayload()
        else -> modsOrModels(path, request, machine)
    }

    private fun mailboxes(machine: DemoAgentMachine) = MailboxList(
        mailboxes = DemoFleetState.mailboxes(machine).map {
            Mailbox(address = it, detail = "6.0K used", manageable = true)
        },
    )

    private fun dkim(machine: DemoAgentMachine) = DkimRecordList(
        records = listOf(
            DkimRecord(
                name = "dkim._domainkey.${machine.deployment.domain}",
                value_ = "v=DKIM1;k=rsa;p=" + "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A".repeat(6),
            ),
        ),
    )

    // Mods and models

    private fun modsOrModels(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Mods/SearchMods" -> modSearch().demoPayload()
        "/gryonixnexusd.v1.Mods/ModVersions" -> modVersions().demoPayload()
        "/gryonixnexusd.v1.Mods/ListModFiles", "/gryonixnexusd.v1.Mods/UploadModFile",
        "/gryonixnexusd.v1.Mods/DeleteModFile" -> modFiles(path, request, machine).demoPayload()
        "/gryonixnexusd.v1.Vaultwarden/GetVaultwardenTwoFactor" ->
            VaultwardenTwoFactor(readable = true, users = 3, users_without_two_factor = 1).demoPayload()
        "/gryonixnexusd.v1.Models/ListModels" -> models(machine).demoPayload()
        "/gryonixnexusd.v1.Models/DeleteModel" -> {
            val asked = DeleteModelRequest.ADAPTER.decode(request)
            DemoAgentState.memory(machine) { it.models.remove(asked.name) }
            models(machine).demoPayload()
        }
        else -> DemoAgentNetworks.answer(path, request, machine)
    }

    private fun modFiles(path: String, request: ByteArray, machine: DemoAgentMachine): ModFileList {
        val service = DemoAgentState.memory(machine) { stored ->
            when {
                path.endsWith("UploadModFile") -> UploadModFileRequest.ADAPTER.decode(request).let {
                    stored.modFiles.getOrPut(it.service_id) { mutableListOf() }.add(it.name)
                    it.service_id
                }
                path.endsWith("DeleteModFile") -> DeleteModFileRequest.ADAPTER.decode(request).let {
                    stored.modFiles[it.service_id]?.remove(it.name)
                    it.service_id
                }
                else -> ListModFilesRequest.ADAPTER.decode(request).service_id
            }
        }
        val names = DemoAgentState.memory(machine) { it.modFiles[service].orEmpty().toList() }
        return ModFileList(
            disk_free_bytes = 41_000_000_000,
            files = names.map {
                ModFile(name = it, slot = ModSlot.MOD_SLOT_MODS, size_bytes = 812_544,
                    modified_unix = System.currentTimeMillis() / 1000)
            },
        )
    }

    private fun modSearch(): ModSearchResult {
        val projects = listOf(
            project("fabric-api", "Fabric API", "The core library every Fabric mod builds on"),
            project("lithium", "Lithium", "Server-side optimisation, no behaviour changes"),
        )
        return ModSearchResult(projects = projects, total = projects.size)
    }

    private fun project(slug: String, title: String, summary: String) = ModProject(
        slug = slug, title = title, description = summary, project_id = slug,
        project_type = "mod", author = "gryonixNexus demo", downloads = 9_400_000,
    )

    private fun modVersions() = ModVersionList(
        versions = listOf(
            ModVersion(
                version_id = "demo-1", version_number = "0.100.1", name = "Fabric API 0.100.1",
                version_type = "release", game_versions = listOf("1.21"), loaders = listOf("fabric"),
            ),
        ),
    )

    private fun models(machine: DemoAgentMachine) = ModelList(
        engine_present = true,
        path = "/var/lib/ollama",
        disk_free_bytes = 41_000_000_000,
        disk_total_bytes = 120_000_000_000,
        models = DemoAgentState.memory(machine) { stored ->
            stored.models.map { Model(name = it, size_bytes = 2_400_000_000) }
        },
    )
}
