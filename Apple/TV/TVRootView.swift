import SwiftUI

struct TVRootView: View {
    @ObservedObject private var tabs = TVTabSettings.shared
    @State private var selection = Self.firstTab

    private static var firstTab: String {
        #if DEBUG
        ProcessInfo.processInfo.environment["GRYONIXNEXUS_TV_TAB"] ?? "servers"
        #else
        "servers"
        #endif
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(tabs.visible) { tab in
                Tab(value: tab.rawValue) {
                    content(for: tab)
                } label: {
                    Label(tab.appTab.title, systemImage: tab.appTab.systemImage)
                }
            }
            Tab(value: "settings") {
                TVSettingsView()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    @ViewBuilder
    private func content(for tab: TVTab) -> some View {
        switch tab {
        case .servers: TVServersView()
        case .vpn: VPNSectionView().licenseLocked()
        case .metrics: MetricsDashboardView().licenseLocked()
        case .containers: ContainersSection().licenseLocked()
        }
    }
}
