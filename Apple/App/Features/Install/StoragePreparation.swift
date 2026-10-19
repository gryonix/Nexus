import AgentClient
import Foundation
import ServerControl
import ServiceCatalog

/// Storage the user picked for one machine
struct StorageChoice: Equatable {
    /// A disk path, or `array:<id>` for a found mirror
    var fastDisk: String?
    /// Second SSD that mirrors the cache disk
    var mirrorDisk: String?
    var buildsRaid = false
    var raidLevel = RaidPlan.Level.raid1
    /// mdadm, ZFS or btrfs
    var raidKind = StorageArray.Kind.md
    var raidDisks: Set<String> = []
    var confirmation = ""
    /// Arrays found on the disks that are brought back
    var importArrays: Set<String> = []
    /// Service data goes on the array, not the main disk
    var dataOnArray = true

    static let arrayPrefix = "array:"

    /// Brings back everything a past install left
    static func defaults(for hardware: ServerHardware) -> StorageChoice {
        var choice = StorageChoice()
        let stopped = StorageArray.all(in: hardware).filter { $0.state == .stopped && $0.kind == .md }
        choice.importArrays = Set(stopped.map(\.id))
        if let mirror = stopped.first(where: \.isCacheMirror) {
            choice.fastDisk = arrayPrefix + mirror.id
        } else if let earlier = hardware.disks.first(where: \.isEarlierCache) {
            choice.fastDisk = earlier.path
        }
        return choice
    }
}

/// One script run before setup, with its success marker
struct StorageStep: Equatable {
    let title: String
    let script: String
    let doneMarker: String
    /// The same work as a typed agent request
    var agentTask: Gryonixnexusd_V1_StorageTaskRequest?
}

extension InstallViewModel.Target {
    var raidPlan: RaidPlan? {
        guard storage.buildsRaid, let hardware else { return nil }
        let disks = RaidPlan.candidates(in: hardware).filter { storage.raidDisks.contains($0.path) }
        return RaidPlan(level: storage.raidLevel, disks: disks, kind: storage.raidKind)
    }

    var arrays: [StorageArray] { hardware.map(StorageArray.all(in:)) ?? [] }

    var fastDisk: ServerDisk? { hardware?.disks.first { $0.path == storage.fastDisk } }

    var mirrorPlan: RaidPlan? {
        guard let first = fastDisk, first.isBlank, let path = storage.mirrorDisk,
              let second = hardware?.disks.first(where: { $0.path == path }) else { return nil }
        return .cacheMirror([first, second])
    }

    var fastPlan: FastStoragePlan? {
        let hot = FastStoragePlan.hotPaths(inText: script.contents)
        if let mirror = mirrorPlan { return FastStoragePlan(target: .device(mirror.device), hotPaths: hot) }
        if let id = storage.fastDisk?.dropFirst(StorageChoice.arrayPrefix.count),
           storage.fastDisk?.hasPrefix(StorageChoice.arrayPrefix) == true,
           let array = arrays.first(where: { $0.id == id }) {
            return FastStoragePlan(target: .device(array.address), hotPaths: hot)
        }
        return fastDisk.map { FastStoragePlan(disk: $0, hotPaths: hot) }
    }

    /// Where the array holding service data is mounted
    var dataArrayMount: String? {
        if let raid = raidPlan, raid.isValid { return raid.mountPoint }
        if let running = arrays.first(where: DashboardViewModel.holdsData) { return running.mountpoint }
        let imported = arrays.first { storage.importArrays.contains($0.id) && !$0.isCacheMirror }
        return imported.flatMap { RaidImportPlan(array: $0).mountPoint }
    }

    /// The mount the services' data goes to, if chosen
    var chosenDataMount: String? {
        storage.dataOnArray ? dataArrayMount : nil
    }

    /// The cache sits on one disk with nothing mirroring it
    var cacheIsSingleDisk: Bool { fastDisk != nil && mirrorPlan == nil }

    /// RAID needs enough disks and the typed confirmation
    var storageIsReady: Bool {
        guard let raid = raidPlan else { return true }
        return raid.isValid && StoragePreparation.confirms(storage.confirmation)
    }

    var storageSteps: [StorageStep] {
        var steps = arrays.filter { $0.state == .stopped && storage.importArrays.contains($0.id) }
            .map { array in
                StorageStep(title: UIL10n.string("Bringing back the %@ array…", array.name),
                            script: RaidImportPlan(array: array).script(),
                            doneMarker: RaidImportPlan.doneMarker)
            }
        if let mirror = mirrorPlan {
            steps.append(StorageStep(title: UIL10n.string("Mirroring the cache disks…"),
                                     script: mirror.script(), doneMarker: RaidPlan.doneMarker))
        }
        if let raid = raidPlan, raid.isValid {
            steps.append(StorageStep(title: UIL10n.string("Building the RAID array…"),
                                     script: raid.script(), doneMarker: RaidPlan.doneMarker))
        }
        if let fast = fastPlan {
            steps.append(StorageStep(title: UIL10n.string("Preparing the cache disk…"),
                                     script: fast.script(), doneMarker: FastStoragePlan.doneMarker))
        }
        return steps
    }
}

enum StoragePreparation {
    struct Failure: LocalizedError {
        let detail: String
        var errorDescription: String? { detail }
    }

    static func confirms(_ typed: String) -> Bool {
        typed.trimmingCharacters(in: .whitespaces)
            .caseInsensitiveCompare(UIL10n.string("ERASE")) == .orderedSame
    }

    /// Uploads the script, runs it as root, checks its marker
    static func run(_ step: StorageStep, runner: any SSHCommandRunner,
                    username: String) async throws {
        _ = try await output(of: step, runner: runner, elevated: username != "root")
    }

    /// Runs the script on `host` and returns its output
    static func output(of step: StorageStep, runner: any SSHCommandRunner, host: SSHHostID = .vps,
                       elevated: Bool) async throws -> String {
        let encoded = Data(step.script.utf8).base64EncodedString()
        let elevate = elevated ? "sudo -n " : ""
        let command = "f=\"$(mktemp)\" && printf '%s' '\(encoded)' | base64 -d > \"$f\" && "
            + "{ \(elevate)bash \"$f\" 2>&1; rc=$?; rm -f \"$f\"; exit $rc; }"
        let result = try await runner.run(command, on: host, timeout: .seconds(900))
        guard result.stdout.contains(step.doneMarker) else {
            let tail = (result.stdout + result.stderr)
                .split(separator: "\n").suffix(6).joined(separator: "\n")
            throw Failure(detail: step.title + "\n" + tail)
        }
        return result.stdout
    }
}
