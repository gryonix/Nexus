import Foundation
import ServerControl

enum WrapperLogText {
    private static let protocolMarkers: [String] = [
        CommandCatalog.Updates.doneMarker,
        CommandCatalog.Updates.updatedMarker,
        CommandCatalog.Updates.rolledBackMarker,
        CommandCatalog.Updates.failedMarker,
        CommandCatalog.Updates.availableMarker,
        CommandCatalog.Updates.currentMarker,
        CommandCatalog.Updates.unknownMarker,
        CommandCatalog.Backups.controlDoneMarker,
        CommandCatalog.Backups.backupDoneMarker,
        CommandCatalog.Backups.estimateMarker,
        CommandCatalog.Restore.doneMarker,
        CommandCatalog.Uninstall.doneMarker,
    ]

    static func isProtocol(_ line: String) -> Bool {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        return protocolMarkers.contains { trimmed.hasPrefix($0) }
    }

    static func headline(_ line: String) -> String? {
        let text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("backing up ") { return UIL10n.string("Making a backup first, then updating…") }
        if text.hasPrefix("waiting for ") { return UIL10n.string("Waiting for the containers to start…") }
        return nil
    }

    static func readable(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !isProtocol(String($0)) }
            .joined(separator: "\n")
    }
}
