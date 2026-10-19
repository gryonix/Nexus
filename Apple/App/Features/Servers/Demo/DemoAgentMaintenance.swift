import AgentClient
import Foundation
import ServerControl
import SwiftProtobuf

extension DemoAgentState {
    /// Backups, updates, the agent's own update and the job list
    func maintenance(_ path: String, _ request: Data,
                     _ machine: DemoAgentMachine) async throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Backup/ListBackups":
            let asked = try Gryonixnexusd_V1_ListBackupsRequest(serializedBytes: request)
            return await backupList(asked.serviceID, machine).demoPayload
        case "/gryonixnexusd.v1.Backup/ListAllBackups":
            return await allBackups(machine).demoPayload
        case "/gryonixnexusd.v1.Backup/EstimateBackup":
            var answer = Gryonixnexusd_V1_BackupEstimate()
            answer.dataBytes = 14_400_000
            answer.freeBytes = 41_000_000_000
            return answer.demoPayload
        case "/gryonixnexusd.v1.Backup/DeleteBackup":
            let asked = try Gryonixnexusd_V1_DeleteBackupRequest(serializedBytes: request)
            await DemoFleetState.shared.deleteArchive(named: (asked.path as NSString).lastPathComponent,
                                                      deployment: machine.id,
                                                      containers: machine.containers)
            return await backupList(asked.serviceID, machine).demoPayload
        case "/gryonixnexusd.v1.Backup/TestBackupDestination":
            var answer = Gryonixnexusd_V1_BackupDestinationTest()
            answer.ok = true
            return answer.demoPayload
        default:
            return try await schedules(path, request, machine)
        }
    }

    private func allBackups(_ machine: DemoAgentMachine) async -> Gryonixnexusd_V1_AllBackups {
        var all = Gryonixnexusd_V1_AllBackups()
        var seen = Set<String>()
        for service in machine.deployment.installedServices {
            guard let id = AgentServiceMapping.agentID(for: service.id), seen.insert(id).inserted else { continue }
            all.lists.append(await backupList(id, machine))
        }
        return all
    }

    private func backupList(_ service: String,
                            _ machine: DemoAgentMachine) async -> Gryonixnexusd_V1_BackupList {
        let archives = await DemoFleetState.shared.archives(of: service, deployment: machine.id,
                                                            containers: machine.containers)
        var list = Gryonixnexusd_V1_BackupList()
        list.serviceID = service
        list.directory = "/opt/backups/\(service)"
        list.archives = archives.map { archive in
            var entry = Gryonixnexusd_V1_BackupArchive()
            entry.name = archive.name
            entry.path = "/opt/backups/\(service)/\(archive.name)"
            entry.sizeBytes = Int64(archive.bytes)
            entry.modifiedAt = Int64(archive.made.timeIntervalSince1970 * 1000)
            return entry
        }
        return list
    }

    // MARK: - Schedules

    private func schedules(_ path: String, _ request: Data,
                           _ machine: DemoAgentMachine) async throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Backup/GetBackupSchedule":
            return await backupPolicy(machine).demoPayload
        case "/gryonixnexusd.v1.Backup/SetBackupSchedule":
            let asked = try Gryonixnexusd_V1_SetBackupScheduleRequest(serializedBytes: request)
            await DemoFleetState.shared.setBackupSchedule(asked.schedule, deployment: machine.id,
                                                          containers: machine.containers)
            return await backupPolicy(machine, services: asked.services,
                                      retention: asked.retention).demoPayload
        case "/gryonixnexusd.v1.Backup/SetBackupDestination", "/gryonixnexusd.v1.Backup/SetBackupDrives":
            return await backupPolicy(machine).demoPayload
        case "/gryonixnexusd.v1.Update/GetUpdatePolicy":
            return await updatePolicy(machine).demoPayload
        case "/gryonixnexusd.v1.Update/SetUpdateSchedule":
            let asked = try Gryonixnexusd_V1_SetUpdateScheduleRequest(serializedBytes: request)
            await DemoFleetState.shared.setUpdateSchedule(asked.schedule, deployment: machine.id,
                                                          containers: machine.containers)
            return await updatePolicy(machine, services: asked.services).demoPayload
        case "/gryonixnexusd.v1.Update/CheckUpdates":
            return await updateCheck(machine).demoPayload
        default:
            return try agentUpdateOrJobs(path, request, machine)
        }
    }

    private func backupPolicy(_ machine: DemoAgentMachine, services: [String]? = nil,
                              retention: Int32 = 3) async -> Gryonixnexusd_V1_BackupSchedulePolicy {
        var answer = Gryonixnexusd_V1_BackupSchedulePolicy()
        answer.schedule = await DemoFleetState.shared.backupSchedule(of: machine.id,
                                                                     containers: machine.containers)
        answer.retention = retention
        answer.services = services ?? machine.containers
        answer.destinationPublicKey = "ssh-ed25519 DEMO+BACKUP+DESTINATION+KEY"
        answer.drives = Self.demoDrives
        return answer
    }

    /// One fictional USB drive, plugged in and half full
    private static var demoDrives: Gryonixnexusd_V1_BackupDrives {
        var drives = Gryonixnexusd_V1_BackupDrives()
        drives.mode = .both
        drives.encrypt = true
        drives.uuids = [BackupDrivesDemo.uuid]
        drives.passphraseStored = true
        drives.lastCopyAt = Int64(Date().timeIntervalSince1970) - 3 * 3600
        drives.lastCopyOk = true
        var status = Gryonixnexusd_V1_BackupDriveStatus()
        status.uuid = BackupDrivesDemo.uuid
        status.mounted = true
        status.sizeBytes = 61_530_439_680
        status.freeBytes = 29_000_000_000
        status.mountPoint = "/srv/gryonix-backup/usb1"
        drives.drives = [status]
        return drives
    }

    private func updatePolicy(_ machine: DemoAgentMachine,
                              services: [String]? = nil) async -> Gryonixnexusd_V1_UpdatePolicy {
        var answer = Gryonixnexusd_V1_UpdatePolicy()
        answer.schedule = await DemoFleetState.shared.updateSchedule(of: machine.id,
                                                                     containers: machine.containers)
        answer.services = services ?? machine.containers
        return answer
    }

    private func updateCheck(_ machine: DemoAgentMachine) async -> Gryonixnexusd_V1_UpdateCheckResult {
        let waiting = await DemoFleetState.shared.updatable(of: machine.id,
                                                            containers: machine.containers)
        var answer = Gryonixnexusd_V1_UpdateCheckResult()
        answer.services = machine.containers.map { id in
            var status = Gryonixnexusd_V1_ServiceUpdateStatus()
            status.serviceID = id
            status.availability = waiting.contains(id) ? .available : .current
            if waiting.contains(id) { status.movedImages = ["\(id):latest"] }
            return status
        }
        return answer
    }

    // MARK: - The agent and its jobs

    private func agentUpdateOrJobs(_ path: String, _ request: Data,
                                   _ machine: DemoAgentMachine) throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.AgentUpdate/GetAgentUpdateStatus":
            var answer = Gryonixnexusd_V1_AgentUpdateStatus()
            answer.installedVersion = DemoAgentOffer.installedVersion
            answer.updateAvailable = DemoAgentOffer.publishedVersion != nil
            answer.availableVersion = DemoAgentOffer.publishedVersion ?? ""
            return answer.demoPayload
        case "/gryonixnexusd.v1.Jobs/ListJobs":
            var list = Gryonixnexusd_V1_JobList()
            list.jobs = memory(machine).jobs
            return list.demoPayload
        case "/gryonixnexusd.v1.Jobs/CancelJob":
            let asked = try Gryonixnexusd_V1_CancelJobRequest(serializedBytes: request)
            var stored = memory(machine)
            stored.jobs.removeAll { $0.jobID == asked.jobID }
            write(stored, for: machine)
            var job = Gryonixnexusd_V1_Job()
            job.jobID = asked.jobID
            job.outcome = .cancelled
            return job.demoPayload
        default:
            return try vault(path, request, machine)
        }
    }

    // MARK: - The shared vault

    func vault(_ path: String, _ request: Data,
               _ machine: DemoAgentMachine) throws -> Data? {
        switch path {
        case "/gryonixnexusd.v1.Vault/GetVault":
            return snapshot(machine).demoPayload
        case "/gryonixnexusd.v1.Vault/PutVaultEntries":
            let asked = try Gryonixnexusd_V1_PutVaultEntriesRequest(serializedBytes: request)
            var stored = memory(machine)
            for entry in asked.entries {
                stored.vault[entry.id] = (try? entry.serializedData().base64EncodedString()) ?? ""
            }
            write(stored, for: machine)
            return snapshot(machine).demoPayload
        case "/gryonixnexusd.v1.Vault/DeleteVaultEntry":
            let asked = try Gryonixnexusd_V1_DeleteVaultEntryRequest(serializedBytes: request)
            var stored = memory(machine)
            stored.vault[asked.id] = nil
            write(stored, for: machine)
            return snapshot(machine).demoPayload
        default:
            return nil
        }
    }

    private func snapshot(_ machine: DemoAgentMachine) -> Gryonixnexusd_V1_VaultSnapshot {
        var answer = Gryonixnexusd_V1_VaultSnapshot()
        answer.revision = Int64(memory(machine).vault.count)
        answer.entries = memory(machine).vault.values.compactMap { stored in
            guard let data = Data(base64Encoded: stored) else { return nil }
            return try? Gryonixnexusd_V1_VaultEntry(serializedBytes: data)
        }
        return answer
    }

    // MARK: - Metrics the collector kept

    func history(bucket: String, limit: UInt32,
                 machine: DemoAgentMachine) -> Gryonixnexusd_V1_MetricsHistoryResponse {
        let profile = DemoServer.profile(deploymentID: machine.id, host: .vps) ?? .busyHost
        let count = Int(limit == 0 ? 120 : min(limit, 720))
        let step = Self.seconds(in: bucket)
        var answer = Gryonixnexusd_V1_MetricsHistoryResponse()
        answer.bucket = bucket
        answer.points = (0..<count).reversed().map { index in
            var point = Gryonixnexusd_V1_MetricsHistoryPoint()
            let at = Date().addingTimeInterval(-Double(index) * step)
            point.at = Int64(at.timeIntervalSince1970 * 1000)
            point.cpuPercent = 18 + 12 * sin(Double(index) / 9)
            point.memTotalBytes = profile.memTotalBytes
            point.memUsedBytes = Int64(Double(profile.memTotalBytes) * profile.memUsedFraction)
            point.diskTotalBytes = profile.diskTotalBytes
            point.diskUsedBytes = Int64(Double(profile.diskTotalBytes) * profile.diskUsedFraction)
            point.netReceivedPerSecond = 120_000 + 40_000 * cos(Double(index) / 7)
            point.netSentPerSecond = 60_000 + 20_000 * sin(Double(index) / 5)
            point.load1 = 0.6 + 0.3 * sin(Double(index) / 11)
            return point
        }
        return answer
    }

    private static func seconds(in bucket: String) -> Double {
        switch bucket {
        case "10s": return 10
        case "1m": return 60
        case "10m": return 600
        case "1h": return 3_600
        case "1d": return 86_400
        case "1w": return 604_800
        default: return 60
        }
    }
}
