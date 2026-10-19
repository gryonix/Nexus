import SwiftUI

struct TabBarSettingsView: View {
    @ObservedObject private var tabs = TabBarSettings.shared
    @AppStorage(MetricsDisplaySettings.placementKey)
    private var placementRaw = MetricsPlacement.both.rawValue
    @AppStorage(TerminalDisplaySettings.placementKey)
    private var terminalPlacementRaw = TerminalPlacement.server.rawValue
    @AppStorage(ContainersDisplaySettings.placementKey)
    private var containersPlacementRaw = ContainersPlacement.server.rawValue
    @AppStorage(VPNDisplaySettings.placementKey)
    private var vpnPlacementRaw = VPNPlacement.both.rawValue

    var body: some View {
        ReorderableList {
            Section {
                ForEach(tabs.order) { tab in
                    row(for: tab)
                }
                .onMove { tabs.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                InfoSectionHeader("Sections") {
                    #if os(macOS)
                    Text("Drag to reorder, or use the arrows. Settings is always shown.")
                    #else
                    Text("Drag to reorder. Settings is always shown.")
                    #endif
                }
            }

            Section {
                WrappingPicker("Opens on", selection: Binding(
                    get: { tabs.effectiveStartTab },
                    set: { tabs.startTab = $0 }
                )) {
                    ForEach(tabs.visibleTabs) { tab in
                        Label { Text(tab.title) } icon: { tab.icon }.tag(tab)
                    }
                }
            }

            Section {
                WrappingPicker("Show metrics in", selection: placement(
                    $placementRaw, MetricsDisplaySettings.placement(from:))) {
                    ForEach(MetricsPlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                WrappingPicker("Show VPN devices in", selection: placement(
                    $vpnPlacementRaw, VPNDisplaySettings.placement(from:))) {
                    ForEach(VPNPlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                WrappingPicker("Show containers in", selection: placement(
                    $containersPlacementRaw, ContainersDisplaySettings.placement(from:))) {
                    ForEach(ContainersPlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                WrappingPicker("Show the terminal in", selection: placement(
                    $terminalPlacementRaw, TerminalDisplaySettings.placement(from:))) {
                    ForEach(TerminalPlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
            } header: {
                InfoSectionHeader("Where things appear", note: "The Metrics, VPN, Containers and Terminal tabs show every server at once; inside a server is the same thing for that one machine. Choosing one place hides the tab — it changes nothing on the servers themselves. Containers and Terminal start inside the server only.")
            }
        }
        .navigationTitle("Sections")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        #endif
    }

    private func placement<P: RawRepresentable>(
        _ raw: Binding<String>, _ parse: @escaping (String) -> P
    ) -> Binding<P> where P.RawValue == String {
        Binding(get: { parse(raw.wrappedValue) }, set: { raw.wrappedValue = $0.rawValue })
    }

    private func row(for tab: AppTab) -> some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { tabs.isVisible(tab) },
                set: { tabs.setVisible($0, for: tab) }
            )) {
                Label { Text(tab.title) } icon: { tab.icon }
            }
            .disabled(!tab.canBeHidden)

            #if os(macOS)
            reorderButtons(for: tab)
            #endif
        }
    }

    #if os(macOS)
    /// What the drag gesture is on iOS
    private func reorderButtons(for tab: AppTab) -> some View {
        HStack(spacing: 4) {
            Button {
                tabs.moveUp(tab)
            } label: {
                Label("Move up", systemImage: "chevron.up")
                    .labelStyle(.iconOnly)
            }
            .disabled(!tabs.canMoveUp(tab))

            Button {
                tabs.moveDown(tab)
            } label: {
                Label("Move down", systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
            }
            .disabled(!tabs.canMoveDown(tab))
        }
        .buttonStyle(.borderless)
        .fixedSize()
    }
    #endif
}

#Preview {
    NavigationStack { TabBarSettingsView() }
}
