import ServiceCatalog
import SwiftUI

/// Words for array changes, array kinds and disk jobs
enum StorageChangeText {
    static func title(_ action: ArrayChange.Action) -> String {
        switch action {
        case .addSpare: return UIL10n.string("Add a spare disk")
        case .grow: return UIL10n.string("Add a disk")
        case .replace: return UIL10n.string("Replace a working disk")
        case .detach: return UIL10n.string("Take a disk out to swap it")
        case .remove: return UIL10n.string("Remove a disk and move its data")
        case .changeLevel: return UIL10n.string("Change the RAID level")
        case .check: return UIL10n.string("Check the array for errors")
        case .delete: return UIL10n.string("Delete the array")
        }
    }

    static func running(_ action: ArrayChange.Action) -> String {
        switch action {
        case .addSpare: return UIL10n.string("Adding the spare disk…")
        case .grow: return UIL10n.string("Adding the disk…")
        case .replace: return UIL10n.string("Starting the copy onto the new disk…")
        case .detach: return UIL10n.string("Taking the disk out…")
        case .remove: return UIL10n.string("Moving the data off the disk…")
        case .changeLevel: return UIL10n.string("Changing the level…")
        case .check: return UIL10n.string("Starting the check…")
        case .delete: return UIL10n.string("Deleting the array…")
        }
    }

    static func explanation(_ action: ArrayChange.Action) -> String {
        switch action {
        case .addSpare:
            return UIL10n.string("The new disk waits unused. When a disk in the array fails, the array rebuilds onto it by itself.")
        case .grow:
            return UIL10n.string("The new disk joins the array. A mirror gets one more copy; other levels get more space.")
        case .replace:
            return UIL10n.string("Everything on the chosen disk is copied onto the new one while the array stays protected. Then the old disk leaves the array and can be pulled out.")
        case .detach:
            return UIL10n.string("The disk leaves the array so you can pull it out. Until a new disk is put in, the array has less protection.")
        case .remove:
            return UIL10n.string("The data on the chosen disk is moved onto the others, then the disk leaves the array. The data must fit on the disks that stay.")
        case .changeLevel:
            return UIL10n.string("The data is rewritten at the new level in the background. The server keeps working.")
        case .check:
            return UIL10n.string("Every block is read and compared, and repaired where the array can. It runs in the background.")
        case .delete:
            return UIL10n.string("The array is taken apart and everything on its disks is erased. The disks become free.")
        }
    }

    static func kind(_ kind: StorageArray.Kind) -> String {
        switch kind {
        case .zfs: return "ZFS"
        case .btrfs: return "Btrfs"
        default: return UIL10n.string("Linux RAID (mdadm)")
        }
    }

    static func kindNote(_ kind: StorageArray.Kind) -> String {
        switch kind {
        case .zfs:
            return UIL10n.string("Checks every block for damage. Needs more memory; on Debian the ZFS module is built first, which takes a while.")
        case .btrfs:
            return UIL10n.string("Flexible: disks of different sizes, added and removed at any time. RAID 5 and 6 are left out; they are not safe on btrfs.")
        default:
            return UIL10n.string("The classic: works on every Linux server, formatted as ext4.")
        }
    }

    static func job(_ job: DiskJob) -> String {
        let action = ArrayChange.Action(rawValue: job.action).map(title) ?? job.action
        return "\(action) — \(job.target)"
    }

    static func outcome(_ job: DiskJob) -> String {
        switch job.outcome {
        case .running: return UIL10n.string("Running")
        case .done: return UIL10n.string("Finished")
        case .failed: return UIL10n.string("Failed")
        }
    }

    static func member(_ path: String, in hardware: ServerHardware?) -> String {
        let name = path.replacingOccurrences(of: "/dev/", with: "")
        guard let hardware, let disk = hardware.disks.first(where: { $0.path == hardware.diskPath(containing: path) })
        else { return name }
        let serial = disk.serial.isEmpty ? nil : UIL10n.string("S/N %@", disk.serial)
        return ([name, disk.model] + [serial].compactMap { $0 }).filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
