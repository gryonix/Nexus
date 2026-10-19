import AgentClient
import Foundation
import ServiceCatalog

/// Disk steps that the agent can run as root
extension StorageStep {
    static func diskHealth(_ paths: [String]) -> StorageStep {
        var task = Gryonixnexusd_V1_StorageTaskRequest()
        task.kind = .diskHealth
        task.diskHealth.disks = paths
        return StorageStep(title: UIL10n.string("Reading the disks…"), script: DiskHealth.script(paths: paths),
                           doneMarker: DiskHealth.doneMarker, agentTask: task)
    }

    static func raid(_ plan: RaidPlan, title: String) -> StorageStep {
        var task = Gryonixnexusd_V1_StorageTaskRequest()
        task.kind = .raidCreate
        task.raidCreate.level = UInt32(plan.level.rawValue)
        task.raidCreate.disks = plan.disks.map(\.path)
        task.raidCreate.name = plan.name
        task.raidCreate.mountPoint = plan.mountPoint ?? ""
        task.raidCreate.kind = agentKind(plan.kind)
        task.raidCreate.identities = plan.disks.map { agentIdentity($0.identity) }
        return StorageStep(title: title, script: plan.script(), doneMarker: RaidPlan.doneMarker, agentTask: task)
    }

    static func importing(_ array: StorageArray) -> StorageStep {
        let plan = RaidImportPlan(array: array)
        var task = Gryonixnexusd_V1_StorageTaskRequest()
        task.kind = .raidImport
        task.raidImport.kind = array.kind == .zfs ? .zfs : .md
        task.raidImport.address = array.kind == .zfs ? array.name : array.address
        task.raidImport.name = array.name
        task.raidImport.uuid = array.uuid ?? ""
        task.raidImport.mountPoint = plan.mountPoint ?? ""
        return StorageStep(title: UIL10n.string("Bringing back the %@ array…", array.name), script: plan.script(),
                           doneMarker: RaidImportPlan.doneMarker, agentTask: task)
    }

    static func repair(_ array: StorageArray, with disk: ServerDisk) -> StorageStep {
        var task = Gryonixnexusd_V1_StorageTaskRequest()
        task.kind = .raidRepair
        task.raidRepair.kind = array.kind == .zfs ? .zfs : .md
        task.raidRepair.address = array.kind == .zfs ? array.name : array.address
        task.raidRepair.name = array.name
        task.raidRepair.failed = array.failed.first ?? ""
        task.raidRepair.replacement = disk.path
        task.raidRepair.identities = [agentIdentity(disk.identity)]
        return StorageStep(title: UIL10n.string("Adding %@ to the array…", disk.name),
                           script: RaidRepairPlan(array: array, replacement: disk).script(),
                           doneMarker: RaidRepairPlan.doneMarker, agentTask: task)
    }

    static func cacheProbe(title: String, script: String, doneMarker: String) -> StorageStep {
        var task = Gryonixnexusd_V1_StorageTaskRequest()
        task.kind = .cacheProbe
        return StorageStep(title: title, script: script, doneMarker: doneMarker, agentTask: task)
    }

    static func cacheMove(_ move: FastStorageMove) -> StorageStep {
        var task = Gryonixnexusd_V1_StorageTaskRequest()
        task.kind = .cacheMove
        switch move.target {
        case .device(let path): task.cacheMove.device = path
        case .folder(let mount): task.cacheMove.folderOn = mount
        }
        task.cacheMove.projects = move.projects.map(Self.project)
        return StorageStep(title: UIL10n.string("Moving to the cache disk…"), script: move.script(),
                           doneMarker: FastStorageMove.doneMarker, agentTask: task)
    }

    static func cacheRestore(_ projects: [FastStorageMove.Project]) -> StorageStep {
        var task = Gryonixnexusd_V1_StorageTaskRequest()
        task.kind = .cacheRestore
        task.cacheRestore.projects = projects.map(Self.project)
        return StorageStep(title: UIL10n.string("Bringing the folders back…"),
                           script: FastStorageRestore.script(projects: projects),
                           doneMarker: FastStorageRestore.doneMarker, agentTask: task)
    }

    static func cacheCleanup(_ paths: [String]) -> StorageStep {
        var task = Gryonixnexusd_V1_StorageTaskRequest()
        task.kind = .cacheCleanup
        task.cacheCleanup.paths = paths
        return StorageStep(title: UIL10n.string("Deleting old copies…"),
                           script: FastStorageRestore.cleanupScript(paths: paths),
                           doneMarker: FastStorageRestore.cleanupDoneMarker, agentTask: task)
    }

    private static func agentKind(_ kind: StorageArray.Kind) -> Gryonixnexusd_V1_StorageArrayKind {
        switch kind {
        case .zfs: return .zfs
        case .btrfs: return .btrfs
        default: return .md
        }
    }

    static func change(_ change: ArrayChange, in hardware: ServerHardware) -> StorageStep {
        let spec = change.spec(in: hardware)
        var task = Gryonixnexusd_V1_StorageTaskRequest()
        task.kind = .arrayChange
        task.arrayChange.action = agentAction(spec.action)
        task.arrayChange.kind = agentKind(spec.kind)
        task.arrayChange.address = spec.address
        task.arrayChange.name = spec.name
        task.arrayChange.level = spec.level
        task.arrayChange.member = spec.member
        task.arrayChange.disks = spec.disks
        task.arrayChange.devices = UInt32(max(spec.devices, 0))
        task.arrayChange.newLevel = UInt32(spec.newLevel)
        task.arrayChange.members = spec.members
        task.arrayChange.checkDisks = spec.checkDisks
        task.arrayChange.identities = spec.identities.map(agentIdentity)
        return StorageStep(title: StorageChangeText.running(change.action), script: spec.script(),
                           doneMarker: ArrayChange.doneMarker, agentTask: task)
    }

    private static func agentAction(_ action: ArrayChange.Action) -> Gryonixnexusd_V1_ArrayChangeAction {
        switch action {
        case .addSpare: return .addSpare
        case .grow: return .grow
        case .replace: return .replace
        case .detach: return .detach
        case .remove: return .remove
        case .changeLevel: return .changeLevel
        case .check: return .check
        case .delete: return .delete
        }
    }

    static func format(_ plan: DiskFormatPlan) -> StorageStep {
        var task = Gryonixnexusd_V1_StorageTaskRequest()
        task.kind = .diskFormat
        task.diskFormat.disk = plan.disk
        task.diskFormat.filesystem = plan.filesystem.rawValue
        task.diskFormat.label = plan.label
        task.diskFormat.mountPoint = plan.mountPoint
        if let identity = plan.identity { task.diskFormat.identity = agentIdentity(identity) }
        return StorageStep(title: UIL10n.string("Formatting the disk…"), script: plan.script(),
                           doneMarker: DiskFormatPlan.doneMarker, agentTask: task)
    }

    static func release(_ plan: DiskReleasePlan) -> StorageStep {
        var task = Gryonixnexusd_V1_StorageTaskRequest()
        task.kind = .diskRelease
        task.diskRelease.mountPoint = plan.mountPoint
        return StorageStep(title: UIL10n.string("Disconnecting the disk…"), script: plan.script(),
                           doneMarker: DiskReleasePlan.doneMarker, agentTask: task)
    }

    static func blink(_ disk: ServerDisk) -> StorageStep {
        var task = Gryonixnexusd_V1_StorageTaskRequest()
        task.kind = .diskBlink
        task.diskBlink.disk = disk.path
        return StorageStep(title: UIL10n.string("Blinking the disk's light…"), script: DiskBlink.script(disk: disk.path),
                           doneMarker: DiskBlink.doneMarker, agentTask: task)
    }

    static func driveFormat(_ disk: ServerDisk, name: String) -> StorageStep {
        var task = Gryonixnexusd_V1_StorageTaskRequest()
        task.kind = .driveFormat
        task.driveFormat.disk = disk.path
        task.driveFormat.name = name
        task.driveFormat.identity = agentIdentity(disk.identity)
        return StorageStep(title: UIL10n.string("Formatting the drive…"),
                           script: BackupDriveScripts.format(disk: disk.path, name: name, identity: disk.identity),
                           doneMarker: BackupDriveScripts.formatDone, agentTask: task)
    }

    enum DriveWork: Hashable { case attach, check, eject, forget }

    static func drive(_ work: DriveWork, uuid: String, name: String) -> StorageStep {
        var task = Gryonixnexusd_V1_StorageTaskRequest()
        task.drive.uuid = uuid
        task.drive.name = name
        switch work {
        case .attach:
            task.kind = .driveAttach
            return StorageStep(title: UIL10n.string("Connecting the drive…"), script: BackupDriveScripts.attach(uuid: uuid, name: name),
                               doneMarker: BackupDriveScripts.attachDone, agentTask: task)
        case .check:
            task.kind = .driveCheck
            return StorageStep(title: UIL10n.string("Checking the drive…"), script: BackupDriveScripts.check(uuid: uuid, name: name),
                               doneMarker: BackupDriveScripts.checkDone, agentTask: task)
        case .eject:
            task.kind = .driveEject
            return StorageStep(title: UIL10n.string("Unplugging the drive…"), script: BackupDriveScripts.eject(uuid: uuid, name: name),
                               doneMarker: BackupDriveScripts.ejectDone, agentTask: task)
        case .forget:
            task.kind = .driveForget
            return StorageStep(title: UIL10n.string("Forgetting the drive…"), script: BackupDriveScripts.forget(uuid: uuid, name: name),
                               doneMarker: BackupDriveScripts.forgetDone, agentTask: task)
        }
    }

    private static func agentIdentity(_ identity: DiskIdentity) -> Gryonixnexusd_V1_DiskIdentity {
        var result = Gryonixnexusd_V1_DiskIdentity()
        result.path = identity.path
        result.serial = identity.serial
        result.sizeBytes = UInt64(max(identity.sizeBytes, 0))
        return result
    }

    private static func project(_ project: FastStorageMove.Project) -> Gryonixnexusd_V1_CacheProject {
        var result = Gryonixnexusd_V1_CacheProject()
        result.directory = project.directory
        result.hotPaths = project.hotPaths
        return result
    }
}
