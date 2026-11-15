import Foundation
import ServerControl
import ServiceCatalog

extension DashboardViewModel {
    func loadBackupParts() async {
        do {
            let seam = try await autoBackupSeam()
            backupParts = try await seam.loadParts()
            backupPartsError = nil
        } catch {
            backupPartsError = Self.message(for: error)
        }
    }

    /// Writes the change, keeping what the server answered
    func saveBackupParts(_ change: BackupPartsChange) async {
        let previous = backupParts
        backupParts = backupParts.applying(change)
        do {
            let seam = try await autoBackupSeam()
            try await seam.saveParts(change)
            backupPartsError = nil
        } catch {
            backupParts = previous
            backupPartsError = Self.message(for: error)
        }
    }
}
