import SwiftUI

/// Which Security screen a tapped row opens
enum SecurityRoute: String, Identifiable, Hashable {
    case adminPanels, crowdSec, sshAccess

    var id: String { rawValue }
}

/// One Security row: name, switch, refresh arrow, chevron
struct SecurityRow<Control: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    var tint: Color = .secondary
    var caption: LocalizedStringKey?
    var status: LocalizedStringKey?
    let refreshLabel: LocalizedStringKey
    var isRefreshing = false
    let refresh: () async -> Void
    let open: () -> Void
    @ViewBuilder let control: () -> Control

    #if os(tvOS)
    @State private var hasSwitch = false

    /// One control for the remote: the switch, labelled
    var body: some View {
        ZStack {
            if !hasSwitch { plainRow }
            control()
                .environment(\.securityRowLabel, AnyView(plainRow))
        }
        .onPreferenceChange(SecuritySwitchShown.self) { hasSwitch = $0 }
    }

    private var plainRow: some View {
        HStack(spacing: 10) {
            name
            Spacer(minLength: 8)
            if let status {
                Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
    #else
    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) { name }
                .buttonStyle(.plain)
            Spacer(minLength: 8)
            if let status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            control()
            RefreshButton(label: refreshLabel, isBusy: isRefreshing, action: refresh)
            openArrow
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
    #endif

    private var name: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
    }

    private var openArrow: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

/// The row's own on/off switch
struct SecuritySwitch: View {
    let isOn: Bool
    var isEnabled = true
    let set: (Bool) -> Void

    var body: some View {
        #if os(tvOS)
        Toggle(isOn: Binding(get: { isOn }, set: set)) { rowLabel }
            .disabled(!isEnabled)
            .preference(key: SecuritySwitchShown.self, value: true)
        #else
        Toggle(String(""), isOn: Binding(get: { isOn }, set: set))
            .labelsHidden()
            .disabled(!isEnabled)
        #endif
    }

    #if os(tvOS)
    @Environment(\.securityRowLabel) private var rowLabel
    #endif
}

#if os(tvOS)
/// A switch inside the row replaces its plain label
struct SecuritySwitchShown: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension EnvironmentValues {
    @Entry var securityRowLabel = AnyView(EmptyView())
}
#endif
