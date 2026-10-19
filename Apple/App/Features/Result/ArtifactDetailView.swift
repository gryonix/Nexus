import SwiftUI
import gryonixNexusCore

struct ArtifactDetailView: View {
    let artifact: Artifact
    @State private var copied = false
    @ObservedObject private var license = LicenseStore.shared

    var body: some View {
        if license.status.isActive {
            script
        } else {
            LockCard(reason: LicenseGate.reason)
                .navigationTitle(artifact.fileName)
        }
    }

    private var script: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(artifact.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let path = artifact.suggestedPath {
                    LabeledContent("Where to put it") {
                        Text(path)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }

                Text(artifact.contents)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding()
        }
        .navigationTitle(artifact.fileName)
        .raisedNavigationTitle()
        .toolbar {
            ToolbarItemGroup {
                Button {
                    copyToClipboard(artifact.contents)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }

                if let url = try? ExportController.exportURL(for: artifact) {
                    ShareLink(item: url) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func copyToClipboard(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}
