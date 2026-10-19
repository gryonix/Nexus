#if os(macOS)
import SwiftUI

struct MenuBarSettingsSection: View {
    @ObservedObject private var settings = MenuBarSettings.shared

    var body: some View {
        Section {
            Toggle(isOn: $settings.showsItem) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show in the menu bar")
                    Text("The tunnel's state at a glance, and the switch for it, without opening the window.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $settings.accessoryOnly) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Menu bar only")
                    Text("Hides the Dock icon and the app switcher entry. The menu bar becomes the only way in.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!settings.showsItem)
        } header: {
            Text("Menu bar")
        }
    }
}
#endif
