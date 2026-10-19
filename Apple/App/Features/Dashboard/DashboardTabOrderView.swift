import Foundation
import SwiftUI

struct DashboardTabOrderView: View {
    /// The segments this particular server offers
    let available: [DashboardTab]
    let deploymentID: UUID

    @ObservedObject private var settings = DashboardTabSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReorderableList(phone: .form) {
                Section {
                    ForEach(settings.order) { tab in
                        row(tab)
                    }
                    .onMove { settings.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    InfoSectionHeader("Sections", note: "The switches apply to this server only. The order is the same on every server; a section that a server does not have is never shown on it.")
                }

                Section {
                    WrappingPicker("Opens on", selection: $settings.startTab) {
                        ForEach(settings.order) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                } header: {
                    InfoSectionHeader("Opens on", note: "Which section a server opens on. A server that does not have it opens on its first one.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Arrange sections")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 360)
        #endif
    }

    @ViewBuilder private func row(_ tab: DashboardTab) -> some View {
        if available.contains(tab) {
            Toggle(isOn: Binding(
                get: { settings.isVisible(tab, on: deploymentID) },
                set: { settings.setVisible($0, for: tab, on: deploymentID, available: available) }
            )) {
                label(tab)
            }
            .disabled(!settings.canHide(tab, on: deploymentID, available: available))
        } else {
            LabeledContent {
                Text("Not on this server")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } label: {
                label(tab)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func label(_ tab: DashboardTab) -> some View {
        HStack(spacing: 12) {
            Group {
                if tab == .vpn {
                    BrandMark.vpn(size: 20)
                } else {
                    Image(systemName: tab.systemImage)
                }
            }
            .frame(width: 22)
            .foregroundStyle(.secondary)
            Text(tab.title)
        }
    }
}
