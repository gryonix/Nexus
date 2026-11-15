package com.skaymer.gryonixnexus.app.servers.demo

import gryonixnexusd.v1.Container
import gryonixnexusd.v1.ContainerBackupList
import gryonixnexusd.v1.ContainerBackupPlan
import gryonixnexusd.v1.ContainerBackupSchedule
import gryonixnexusd.v1.ContainerDetail
import gryonixnexusd.v1.ContainerEnvVar
import gryonixnexusd.v1.ContainerGroup
import gryonixnexusd.v1.ContainerGroupKind
import gryonixnexusd.v1.ContainerInventory
import gryonixnexusd.v1.ContainerMount
import gryonixnexusd.v1.ContainerRemovalPreview
import gryonixnexusd.v1.InspectContainerRequest
import gryonixnexusd.v1.PreviewContainerGroupRemovalRequest
import gryonixnexusd.v1.ServiceStatus
import gryonixnexusd.v1.SetContainerGroupNameRequest

/** The containers on a demo machine */
object DemoAgentContainers {
    fun answer(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Containers/ListContainers" -> inventory(machine).demoPayload()
        "/gryonixnexusd.v1.Containers/SetContainerGroupName" -> {
            val asked = SetContainerGroupNameRequest.ADAPTER.decode(request)
            val wanted = asked.display_name.trim()
            DemoAgentState.memory(machine) {
                if (wanted.isEmpty()) it.groupNames.remove(asked.key) else it.groupNames[asked.key] = wanted
            }
            inventory(machine).demoPayload()
        }
        "/gryonixnexusd.v1.Containers/InspectContainer" ->
            detail(InspectContainerRequest.ADAPTER.decode(request).name).demoPayload()
        "/gryonixnexusd.v1.Containers/PreviewContainerGroupRemoval" -> {
            val key = PreviewContainerGroupRemovalRequest.ADAPTER.decode(request).key
            ContainerRemovalPreview(
                key = key,
                containers = listOf("$key-app-1"),
                volumes = listOf("${key}_data"),
                paths = listOf("/opt/$key"),
            ).demoPayload()
        }
        "/gryonixnexusd.v1.Containers/GetContainerBackupPlan",
        "/gryonixnexusd.v1.Containers/SetContainerBackupPlan" -> ContainerBackupPlan().demoPayload()
        "/gryonixnexusd.v1.Containers/GetContainerBackupSchedule",
        "/gryonixnexusd.v1.Containers/SetContainerBackupSchedule" -> ContainerBackupSchedule().demoPayload()
        "/gryonixnexusd.v1.Containers/ListContainerGroupBackups" -> ContainerBackupList().demoPayload()
        "/gryonixnexusd.v1.Containers/ListImages",
        "/gryonixnexusd.v1.Containers/ListVolumes",
        "/gryonixnexusd.v1.Containers/RemoveImage",
        "/gryonixnexusd.v1.Containers/RemoveVolume",
        "/gryonixnexusd.v1.Containers/PruneUnused" -> DemoDockerAssets.answer(path, request, machine)
        else -> null
    }

    fun inventory(machine: DemoAgentMachine): ContainerInventory = DemoAgentState.memory(machine) { stored ->
        val groups = machine.installed
            .filter { it.id.rawValue !in stored.removedGroups }
            .map { group(it.id.rawValue, it.displayName, it.id.rawValue, stored) } +
            group("uptime-kuma", "Uptime Kuma", "", stored)
        ContainerInventory(groups = groups)
    }

    private fun group(key: String, name: String, serviceID: String, memory: DemoAgentState.Memory): ContainerGroup {
        val running = key !in memory.stoppedGroups
        return ContainerGroup(
            key = key,
            kind = if (serviceID.isEmpty()) ContainerGroupKind.CONTAINER_GROUP_KIND_STANDALONE
            else ContainerGroupKind.CONTAINER_GROUP_KIND_COMPOSE_PROJECT,
            derived_name = name,
            display_name = memory.groupNames[key] ?: name,
            renamed = key in memory.groupNames,
            service_id = serviceID,
            status = if (running) ServiceStatus.SERVICE_STATUS_RUNNING else ServiceStatus.SERVICE_STATUS_STOPPED,
            containers = listOf(
                Container(
                    name = if (serviceID.isEmpty()) key else "$key-app-1",
                    image = "$key:latest",
                    state = if (running) "running" else "exited",
                    health = if (running) "healthy" else "",
                    ports = if (running) "127.0.0.1:8080->80/tcp" else "",
                ),
            ),
            config_files = if (serviceID.isEmpty()) emptyList() else listOf("/opt/$key/docker-compose.yml"),
        )
    }

    private fun detail(name: String) = ContainerDetail(
        container = Container(name = name, image = "$name:latest", state = "running", health = "healthy"),
        created_at = "2026-08-16T21:04:11Z",
        restart_policy = "unless-stopped",
        compose_project = name,
        compose_service = "app",
        env = listOf(
            ContainerEnvVar(key = "TZ", value_ = "Europe/Berlin", sensitive = false),
            ContainerEnvVar(key = "DB_PASSWORD", value_ = "••••••••", sensitive = true),
        ),
        mounts = listOf(ContainerMount(source = "/opt/$name/data", destination = "/data", mode = "rw", kind = "bind")),
    )
}
