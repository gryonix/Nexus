import AgentClient
import Foundation

extension DemoAgentState {
    private static let demoImages: [(id: String, repo: String, tag: String, size: UInt64, used: UInt32)] = [
        ("3f8a1c9d2b11", "vaultwarden/server", "1.32", 214_000_000, 1),
        ("a41c77e0d9f2", "nextcloud", "29-apache", 1_120_000_000, 1),
        ("9b02e5a6c831", "postgres", "16", 432_000_000, 1),
        ("0c6d4f1ae277", "postgres", "14", 408_000_000, 0),
        ("e5b3190c7a48", "<none>", "<none>", 96_000_000, 0),
    ]

    private static let demoVolumes: [(name: String, size: UInt64, used: UInt32, managed: Bool)] = [
        ("vaultwarden_data", 48_000_000, 1, true),
        ("nextcloud_html", 2_300_000_000, 1, true),
        ("old_postgres14_data", 640_000_000, 0, false),
        ("scratch_cache", 12_000_000, 0, false),
    ]

    func dockerAssets(_ path: String, _ request: Data, _ machine: DemoAgentMachine) throws -> Data? {
        var stored = memory(machine)
        defer { write(stored, for: machine) }
        switch path {
        case "/gryonixnexusd.v1.Containers/ListImages":
            return Self.imageInventory(stored).demoPayload
        case "/gryonixnexusd.v1.Containers/ListVolumes":
            return Self.volumeInventory(stored).demoPayload
        case "/gryonixnexusd.v1.Containers/RemoveImage":
            let asked = try Gryonixnexusd_V1_RemoveImageRequest(serializedBytes: request)
            return Self.removeImage(asked.reference, &stored).demoPayload
        case "/gryonixnexusd.v1.Containers/RemoveVolume":
            let asked = try Gryonixnexusd_V1_RemoveVolumeRequest(serializedBytes: request)
            return Self.removeVolume(asked.name, &stored).demoPayload
        default:
            let asked = try Gryonixnexusd_V1_PruneUnusedRequest(serializedBytes: request)
            return Self.prune(asked, &stored).demoPayload
        }
    }

    private static func reference(_ row: (id: String, repo: String, tag: String, size: UInt64, used: UInt32)) -> String {
        row.repo == "<none>" ? row.id : "\(row.repo):\(row.tag)"
    }

    private static func imageInventory(_ memory: Memory) -> Gryonixnexusd_V1_ImageInventory {
        var inventory = Gryonixnexusd_V1_ImageInventory()
        for row in demoImages where !memory.removedImages.contains(reference(row)) {
            var image = Gryonixnexusd_V1_DockerImage()
            image.id = row.id
            image.repository = row.repo
            image.tag = row.tag
            image.sizeBytes = row.size
            image.containers = row.used
            image.inUse = row.used > 0
            image.createdSince = "3 weeks ago"
            image.reference = reference(row)
            inventory.images.append(image)
        }
        return inventory
    }

    private static func volumeInventory(_ memory: Memory) -> Gryonixnexusd_V1_VolumeInventory {
        var inventory = Gryonixnexusd_V1_VolumeInventory()
        for row in demoVolumes where !memory.removedVolumes.contains(row.name) {
            var volume = Gryonixnexusd_V1_DockerVolume()
            volume.name = row.name
            volume.driver = "local"
            volume.sizeBytes = row.size
            volume.containers = row.used
            volume.inUse = row.used > 0
            volume.managed = row.managed
            inventory.volumes.append(volume)
        }
        return inventory
    }

    private static func refusal(_ message: String) -> Gryonixnexusd_V1_DockerRemovalResult {
        var result = Gryonixnexusd_V1_DockerRemovalResult()
        result.message = message
        return result
    }

    private static func removeImage(_ reference: String, _ memory: inout Memory) -> Gryonixnexusd_V1_DockerRemovalResult {
        guard let row = demoImages.first(where: { Self.reference($0) == reference }) else {
            return refusal("this host reports no such image")
        }
        if row.used > 0 { return refusal("a container still uses this image") }
        memory.removedImages.insert(reference)
        var result = Gryonixnexusd_V1_DockerRemovalResult()
        result.removed = true
        return result
    }

    private static func removeVolume(_ name: String, _ memory: inout Memory) -> Gryonixnexusd_V1_DockerRemovalResult {
        guard let row = demoVolumes.first(where: { $0.name == name }) else {
            return refusal("this host reports no such volume")
        }
        if row.used > 0 { return refusal("a container still uses this volume") }
        if row.managed { return refusal("this volume belongs to a managed service") }
        memory.removedVolumes.insert(name)
        var result = Gryonixnexusd_V1_DockerRemovalResult()
        result.removed = true
        return result
    }

    private static func prune(_ asked: Gryonixnexusd_V1_PruneUnusedRequest,
                              _ memory: inout Memory) -> Gryonixnexusd_V1_PruneUnusedResult {
        var summary = Gryonixnexusd_V1_PruneUnusedResult()
        if asked.images {
            for row in demoImages where row.used == 0 && !memory.removedImages.contains(reference(row)) {
                memory.removedImages.insert(reference(row))
                summary.imagesRemoved += 1
                summary.reclaimedBytes += row.size
            }
        }
        if asked.volumes {
            for row in demoVolumes where row.used == 0 && !row.managed && !memory.removedVolumes.contains(row.name) {
                memory.removedVolumes.insert(row.name)
                summary.volumesRemoved += 1
                summary.reclaimedBytes += row.size
            }
        }
        return summary
    }
}
