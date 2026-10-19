import AgentClient
import Foundation
import ServerControl
import ServiceCatalog
import SwiftProtobuf

extension DemoAgentState {
    /// The long operations: install, remove, backup, restore, update
    func servicesStream(_ path: String, _ request: Data,
                        _ machine: DemoAgentMachine) async throws -> [DemoAgentStep]? {
        switch path {
        case "/gryonixnexusd.v1.Install/InstallService":
            let asked = try Gryonixnexusd_V1_InstallServiceRequest(serializedBytes: request)
            return await install(asked.serviceID, machine)
        case "/gryonixnexusd.v1.Uninstall/RemoveService":
            let asked = try Gryonixnexusd_V1_RemoveServiceRequest(serializedBytes: request)
            return await remove(asked.serviceID, machine)
        case "/gryonixnexusd.v1.Backup/RunBackup":
            let asked = try Gryonixnexusd_V1_RunBackupRequest(serializedBytes: request)
            return await backup(asked.serviceID, machine)
        case "/gryonixnexusd.v1.Update/RunUpdate":
            let asked = try Gryonixnexusd_V1_RunUpdateRequest(serializedBytes: request)
            return await update(asked.serviceID, machine)
        case "/gryonixnexusd.v1.Restore/RunRestore":
            let asked = try Gryonixnexusd_V1_RunRestoreRequest(serializedBytes: request)
            return restore(asked.serviceID)
        case "/gryonixnexusd.v1.Models/PullModel":
            let asked = try Gryonixnexusd_V1_PullModelRequest(serializedBytes: request)
            return pull(asked.name, machine)
        default:
            return await watchOrContainers(path, request, machine)
        }
    }

    private func install(_ id: String, _ machine: DemoAgentMachine) async -> [DemoAgentStep] {
        await DemoFleetState.shared.install(service: id, deployment: machine.id,
                                            containers: machine.containers)
        let name = ServiceRegistry.service(ServiceID(rawValue: id))?.displayName ?? id
        var steps = Self.progressLines(name, verb: "Installing").map { text -> DemoAgentStep in
            var event = Gryonixnexusd_V1_InstallServiceEvent()
            event.phase = .progress
            event.serviceID = id
            event.text = text
            event.stream = "stdout"
            return event.demoStep(delay: 420)
        }
        var done = Gryonixnexusd_V1_InstallServiceEvent()
        done.phase = .completed
        done.serviceID = id
        steps.append(done.demoStep())
        return steps
    }

    private func remove(_ id: String, _ machine: DemoAgentMachine) async -> [DemoAgentStep] {
        await DemoFleetState.shared.remove(service: id, deployment: machine.id,
                                           containers: machine.containers)
        let name = ServiceRegistry.service(ServiceID(rawValue: id))?.displayName ?? id
        var steps = Self.progressLines(name, verb: "Removing").map { text -> DemoAgentStep in
            var event = Gryonixnexusd_V1_UninstallEvent()
            event.phase = .progress
            event.serviceID = id
            event.text = text
            event.stream = "stdout"
            return event.demoStep()
        }
        var done = Gryonixnexusd_V1_UninstallEvent()
        done.phase = .completed
        done.serviceID = id
        steps.append(done.demoStep())
        return steps
    }

    private func backup(_ id: String, _ machine: DemoAgentMachine) async -> [DemoAgentStep] {
        let made = await DemoFleetState.shared.addArchive(service: id, deployment: machine.id,
                                                          containers: machine.containers)
        var steps = ["==> Backing up \(id)", "Stopping the containers",
                     "Packing the data directory", "Starting the containers"]
            .map { text -> DemoAgentStep in
                var event = Gryonixnexusd_V1_BackupEvent()
                event.phase = .progress
                event.serviceID = id
                event.text = text
                event.stream = "stdout"
                return event.demoStep(delay: 420)
            }
        var done = Gryonixnexusd_V1_BackupEvent()
        done.phase = .completed
        done.serviceID = id
        var archive = Gryonixnexusd_V1_BackupArchive()
        archive.name = made.name
        archive.path = "/opt/backups/\(id)/\(made.name)"
        archive.sizeBytes = Int64(made.bytes)
        archive.modifiedAt = Int64(Date().timeIntervalSince1970 * 1000)
        done.archive = archive
        steps.append(done.demoStep())
        return steps
    }

    private func update(_ id: String, _ machine: DemoAgentMachine) async -> [DemoAgentStep] {
        await DemoFleetState.shared.markUpdated(id, deployment: machine.id,
                                                containers: machine.containers)
        var steps = Self.progressLines(id, verb: "Updating").map { text -> DemoAgentStep in
            var event = Gryonixnexusd_V1_UpdateEvent()
            event.phase = .progress
            event.serviceID = id
            event.text = text
            event.stream = "stdout"
            return event.demoStep(delay: 420)
        }
        var done = Gryonixnexusd_V1_UpdateEvent()
        done.phase = .completed
        done.serviceID = id
        done.outcome = .updated
        steps.append(done.demoStep())
        return steps
    }

    private func restore(_ id: String) -> [DemoAgentStep] {
        var steps = ["==> Restoring \(id)", "Unpacking the archive", "Starting the containers"]
            .map { text -> DemoAgentStep in
                var event = Gryonixnexusd_V1_RestoreEvent()
                event.phase = .progress
                event.serviceID = id
                event.text = text
                event.stream = "stdout"
                return event.demoStep(delay: 420)
            }
        var done = Gryonixnexusd_V1_RestoreEvent()
        done.phase = .completed
        done.serviceID = id
        steps.append(done.demoStep())
        return steps
    }

    private func pull(_ name: String, _ machine: DemoAgentMachine) -> [DemoAgentStep] {
        var stored = memory(machine)
        if !stored.models.contains(name) { stored.models.append(name) }
        write(stored, for: machine)
        var steps: [DemoAgentStep] = (1...4).map { part in
            var event = Gryonixnexusd_V1_ModelPullEvent()
            event.phase = .progress
            event.text = "pulling manifest"
            event.totalBytes = 2_400_000_000
            event.completedBytes = UInt64(600_000_000 * part)
            return event.demoStep(delay: 500)
        }
        var done = Gryonixnexusd_V1_ModelPullEvent()
        done.phase = .completed
        steps.append(done.demoStep())
        return steps
    }

    /// Start, stop or restart one container group
    private func controlGroup(_ asked: Gryonixnexusd_V1_ControlContainerGroupRequest?,
                              _ machine: DemoAgentMachine) -> [DemoAgentStep] {
        guard let asked else { return [] }
        var stored = memory(machine)
        if asked.action == .stop {
            stored.stoppedGroups.insert(asked.key)
        } else {
            stored.stoppedGroups.remove(asked.key)
        }
        write(stored, for: machine)
        var done = Gryonixnexusd_V1_ContainerOperationEvent()
        done.phase = .completed
        done.key = asked.key
        done.action = asked.action
        done.group = inventory(machine).groups.first { $0.key == asked.key } ?? .init()
        return [done.demoStep(delay: 400)]
    }

    private func watchOrContainers(_ path: String, _ request: Data,
                                   _ machine: DemoAgentMachine) async -> [DemoAgentStep]? {
        switch path {
        case "/gryonixnexusd.v1.Install/WatchInstall":
            var done = Gryonixnexusd_V1_InstallServiceEvent()
            done.phase = .completed
            return [done.demoStep(delay: 400)]
        case "/gryonixnexusd.v1.Jobs/WatchJob":
            if let asked = try? Gryonixnexusd_V1_WatchJobRequest(serializedBytes: request),
               await DemoInstallPlans.shared.owns(asked.jobID) {
                return await DemoInstallPlans.shared.log(asked.jobID, from: asked.fromSequence)
            }
            var done = Gryonixnexusd_V1_JobEvent()
            done.phase = .completed
            return [done.demoStep(delay: 400)]
        case "/gryonixnexusd.v1.Containers/ControlContainerGroup":
            let asked = try? Gryonixnexusd_V1_ControlContainerGroupRequest(serializedBytes: request)
            return controlGroup(asked, machine)
        case "/gryonixnexusd.v1.Containers/ContainerGroupLogs":
            return []
        case "/gryonixnexusd.v1.Containers/RunContainerGroupBackup":
            var done = Gryonixnexusd_V1_ContainerBackupEvent()
            done.phase = .completed
            return [done.demoStep(delay: 400)]
        case "/gryonixnexusd.v1.Containers/RemoveContainerGroup":
            let asked = try? Gryonixnexusd_V1_RemoveContainerGroupRequest(serializedBytes: request)
            if let key = asked?.key {
                var stored = memory(machine)
                stored.removedGroups.insert(key)
                write(stored, for: machine)
            }
            var done = Gryonixnexusd_V1_ContainerRemovalEvent()
            done.phase = .completed
            return [done.demoStep(delay: 400)]
        case "/gryonixnexusd.v1.Containers/UpdateContainerGroup":
            var done = Gryonixnexusd_V1_ContainerUpdateEvent()
            done.phase = .completed
            return [done.demoStep(delay: 400)]
        default:
            return nil
        }
    }
}
