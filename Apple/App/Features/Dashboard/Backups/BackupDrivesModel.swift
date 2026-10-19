import Foundation
import ServerControl
import ServiceCatalog

/// USB backup drives of one server and work on them
@MainActor
final class BackupDrivesModel: ObservableObject {
    let dashboard: DashboardViewModel
    let storage: StorageViewModel

    @Published private(set) var state = BackupDrivesState()
    @Published private(set) var isLoading = false
    @Published private(set) var working: String?
    @Published var error: String?
    @Published private(set) var checks: [String: BackupDriveCheck] = [:]
    @Published private(set) var demoHardware: ServerHardware?
    private var demoSeeded = false

    init(dashboard: DashboardViewModel) {
        self.dashboard = dashboard
        storage = StorageViewModel(deployment: dashboard.deployment, host: dashboard.deployment.servicesHost)
    }

    private var isDemo: Bool { DemoFleet.covers(dashboard.deployment) }

    var hardware: ServerHardware? { isDemo ? demoHardware : storage.hardware }

    /// Drives the server sees, plus missing chosen ones
    var drives: [BackupDrive] {
        let names = state.namesByUUID
        let chosen = Dictionary(state.settings.uuids.map { ($0, names[$0] ?? $0) }, uniquingKeysWith: { a, _ in a })
        return BackupDrives.drives(in: hardware, chosen: chosen)
    }

    func isUsed(_ drive: BackupDrive) -> Bool {
        drive.uuid.map(state.settings.uuids.contains) ?? false
    }

    func status(of drive: BackupDrive) -> BackupDriveStatus? {
        state.statuses.first { $0.uuid == drive.uuid }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if isDemo {
            // Same drives on every demo server, agent or not
            demoHardware = ServerHardware.parse(BackupDrivesDemo.probe)
            if !demoSeeded { state = BackupDrivesDemo.state }
            demoSeeded = true
            error = nil
            return
        }
        await storage.load()
        do {
            state = try await dashboard.autoBackupSeam().loadDrives()
            error = nil
        } catch {
            self.error = DashboardViewModel.message(for: error)
        }
    }

    func save(_ settings: BackupDriveSettings) async {
        working = "settings"
        defer { working = nil }
        if isDemo {
            state.settings = settings
            return
        }
        do {
            try await dashboard.autoBackupSeam().saveDrives(settings)
            state = try await dashboard.autoBackupSeam().loadDrives()
            error = nil
        } catch {
            self.error = DashboardViewModel.message(for: error)
        }
    }

    func setUsed(_ drive: BackupDrive, _ used: Bool) async {
        guard let uuid = drive.uuid else { return }
        var settings = state.settings
        settings.uuids.removeAll { $0 == uuid }
        if used { settings.uuids.append(uuid) }
        await save(settings)
    }

    /// Stores the passphrase encrypted copies are made with
    func savePassphrase(_ passphrase: String) async {
        working = "passphrase"
        defer { working = nil }
        await dashboard.loadAutoBackup()
        await dashboard.saveAutoBackup(dashboard.autoBackup, passphrase: passphrase)
        error = dashboard.autoBackupError
        await load()
    }
}

// MARK: - Work on one drive

extension BackupDrivesModel {
    /// Erases a drive, mounts it and starts using it
    func format(_ drive: BackupDrive, name: String) async {
        guard let disk = drive.disk else { return }
        guard let output = await run(.driveFormat(disk, name: name), on: drive) else { return }
        guard let uuid = BackupDriveScripts.formattedUUID(output) ?? (isDemo ? BackupDrivesDemo.uuid : nil) else { return }
        await save(state.settings(formatted: uuid, replacing: drive.uuid, name: name))
        await load()
    }

    func perform(_ work: StorageStep.DriveWork, on drive: BackupDrive) async {
        guard let uuid = drive.uuid else { return }
        if work == .forget, drive.state == .missing, state.isUnmapped(uuid) {
            // Nothing on the server refers to this drive
            await setUsed(drive, false)
            return
        }
        guard let output = await run(.drive(work, uuid: uuid, name: drive.name), on: drive) else { return }
        if work == .check { checks[drive.id] = isDemo ? BackupDrivesDemo.check : BackupDriveCheck.parse(output) }
        if work == .forget, isUsed(drive) { await setUsed(drive, false) }
        await load()
    }

    private func run(_ step: StorageStep, on drive: BackupDrive) async -> String? {
        working = drive.id
        error = nil
        defer { working = nil }
        if isDemo {
            try? await Task.sleep(for: .milliseconds(600))
            return step.doneMarker
        }
        let output = await storage.output(of: step)
        if output == nil { error = storage.stepFailure ?? UIL10n.string("The server did not answer.") }
        return output
    }
}

/// A fictional server's drives, for the demo
enum BackupDrivesDemo {
    static let uuid = "0d3e5f7a-1b2c-4d5e-8f90-a1b2c3d4e5f6"

    static let probe = #"""
    GRYONIXNEXUS_HW_BEGIN
    cpu=4
    mem=8221114368
    arch=aarch64
    rootfree=402653184000
    lsblk={"blockdevices":[{"name":"sda","path":"/dev/sda","size":500107862016,"rota":false,"type":"disk","model":"Demo SSD","tran":"sata","children":[{"name":"sda1","path":"/dev/sda1","type":"part","mountpoint":"/","fstype":"ext4"}]},{"name":"sdb","path":"/dev/sdb","size":61530439680,"rota":false,"type":"disk","model":"Demo Stick","tran":"usb","rm":true,"hotplug":true,"children":[{"name":"sdb1","path":"/dev/sdb1","type":"part","mountpoint":"/srv/gryonix-backup/usb1","fstype":"ext4","label":"gnxb-usb1","uuid":"0d3e5f7a-1b2c-4d5e-8f90-a1b2c3d4e5f6"}]},{"name":"sdc","path":"/dev/sdc","size":1000204886016,"rota":true,"type":"disk","model":"Demo Portable","tran":"usb","rm":false,"hotplug":true}]}
    GRYONIXNEXUS_HW_END
    """#

    /// One drive in use, half full, copied recently
    static var state: BackupDrivesState {
        BackupDrivesState(
            settings: BackupDriveSettings(uuids: [uuid]),
            statuses: [BackupDriveStatus(uuid: uuid, mounted: true, sizeBytes: 61_530_439_680,
                                         freeBytes: 29_000_000_000, mountPoint: "/srv/gryonix-backup/usb1")],
            lastCopy: Date().addingTimeInterval(-3 * 3600),
            lastCopySucceeded: true,
            hasPassphrase: true)
    }

    static var check: BackupDriveCheck {
        var check = BackupDriveCheck()
        check.filesystem = .clean
        check.writeBytesPerSecond = 31_457_280
        check.readBytesPerSecond = 104_857_600
        return check
    }
}
