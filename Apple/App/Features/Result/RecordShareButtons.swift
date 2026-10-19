import SwiftUI
import gryonixNexusCore

struct RecordShareButtons: View {
    /// The records spelled out as text, for the clipboard
    let copyText: String
    let zoneFile: Artifact?
    let csvFile: Artifact?

    @ObservedObject private var license = LicenseStore.shared

    var body: some View {
        if license.status.isActive {
            buttons
        } else {
            lockedButtons
        }
    }

    @ViewBuilder
    private var lockedButtons: some View {
        Button { LicensePrompt.shared.allow() } label: {
            Label("Copy records", systemImage: "lock.fill")
        }
        .rowActionButtonStyle()
        if zoneFile != nil {
            Button { LicensePrompt.shared.allow() } label: {
                Label("Import file (zone)", systemImage: "lock.fill")
            }
        }
        if csvFile != nil {
            Button { LicensePrompt.shared.allow() } label: {
                Label("Import file (CSV)", systemImage: "lock.fill")
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button {
            copyToClipboard(copyText)
        } label: {
            Label("Copy records", systemImage: "doc.on.doc")
        }
        .rowActionButtonStyle()
        if let zoneFile, let url = Self.artifactURL(zoneFile) {
            ShareLink(item: url) {
                Label("Import file (zone)", systemImage: "square.and.arrow.up")
            }
        }
        if let csvFile, let url = Self.artifactURL(csvFile) {
            ShareLink(item: url) {
                Label("Import file (CSV)", systemImage: "tablecells")
            }
        }
    }

    static func artifactURL(_ artifact: Artifact) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(artifact.fileName)
        do {
            try artifact.contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func copyToClipboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
