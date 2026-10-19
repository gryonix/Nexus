#if os(iOS)
import SwiftUI

struct CustomTabBar: View {
    let tabs: [AppTab]
    @Binding var selection: AppTab
    let tunnelActive: Bool
    let onReselect: (AppTab) -> Void

    @AppStorage(AppAccentSettings.choiceKey)
    private var accentRaw = AppAccentSettings.storedChoice().rawValue
    @AppStorage(AppIconSettings.choiceKey)
    private var iconRaw = AppIconChoice.default.rawValue

    private var selectedTint: Color {
        let accent = AppAccentChoice(rawValue: accentRaw) ?? .app
        let icon = AppIconChoice(rawValue: iconRaw) ?? .default
        return accent.tint(icon: icon) ?? Color("AccentColor")
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 10)
            GlassSegmentStrip(
                items: tabs.map { tab in
                    StripItem(id: tab.rawValue,
                              title: UIL10n.string(tab.titleKey),
                              identifier: "shell.section.\(tab.rawValue)",
                              iconName: tab.barIconName(tunnelActive: tunnelActive))
                },
                selection: Binding(
                    get: { selection.rawValue },
                    set: { id in
                        guard let tab = AppTab(rawValue: id), tab != selection else { return }
                        selection = tab
                    }),
                identifier: "shell.sections",
                probe: "shell",
                menu: { id in
                    AppTab(rawValue: id).map(TabBarMenuPresenter.customBarMenu(for:))
                },
                onReselect: { id in
                    guard let tab = AppTab(rawValue: id) else { return }
                    onReselect(tab)
                },
                tabBarStyle: true,
                selectedTint: selectedTint,
                dragToSwitch: true)
            .appTourTarget(.sectionBar)
            Spacer(minLength: 10)
        }
        .padding(.top, 4)
        .padding(.bottom, Self.restingOffset)
    }

    static var restingOffset: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 0 : -14
    }

    static let totalFootprint: CGFloat = 96
}

private struct BarClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var barClearance: CGFloat {
        get { self[BarClearanceKey.self] }
        set { self[BarClearanceKey.self] = newValue }
    }
}
#endif
