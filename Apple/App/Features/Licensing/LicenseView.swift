import SwiftUI
import gryonixNexusCore

/// License: status, plans, restore, activation code and devices.
struct LicenseView: View {
    var reason: LicenseGate.Reason?
    @ObservedObject private var license = LicenseStore.shared

    var body: some View {
        CardList {
            LicenseStatusSection(reason: reason)
            if !license.status.isActive || isSubscription {
                LicensePlansSection()
            }
            LicenseRestoreSection()
            LicenseCodeSection()
            if license.code != nil { LicenseDevicesSection() }
            LicenseDemoSection()
        }
        .navigationTitle(Text("License"))
        .task { await license.refreshIfDue() }
    }

    private var isSubscription: Bool {
        if case .active(let plan, _, _) = license.status { return plan != .lifetime }
        return false
    }
}

struct LicenseStatusSection: View {
    var reason: LicenseGate.Reason?
    @ObservedObject private var license = LicenseStore.shared

    var body: some View {
        Section {
            if let reason {
                Label(LicenseGate.message(for: reason), systemImage: "lock.fill")
                    .font(.headline)
            }
            LabeledContent {
                Text(statusText).foregroundStyle(.secondary)
            } label: {
                Label("Status", systemImage: "checkmark.seal")
            }
        } footer: {
            Text("One license unlocks gryonixNexus on up to five devices.")
        }
    }

    private var statusText: String { Self.text(for: license.status) }

    static func text(for status: LicenseStore.Status) -> String {
        switch status {
        case .demo: return UIL10n.string("Demo")
        case .expired: return UIL10n.string("Subscription ended")
        case .active(let plan, let expires, _): return describe(plan, expires)
        }
    }

    static func describe(_ plan: LicenseToken.Plan, _ expires: Date?) -> String {
        let name = planName(plan)
        guard let expires else { return name }
        return UIL10n.string("%@, until %@", name, expires.formatted(date: .abbreviated, time: .omitted))
    }

    static func planName(_ plan: LicenseToken.Plan) -> String {
        switch plan {
        case .monthly: return UIL10n.string("Monthly")
        case .yearly: return UIL10n.string("Yearly")
        case .lifetime: return UIL10n.string("Forever")
        }
    }
}

struct LicenseDemoSection: View {
    @AppStorage(DemoServer.enabledKey) private var demoFleet = true

    var body: some View {
        Section {
            Toggle(isOn: $demoFleet) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Demo fleet")
                    Text("Shows invented servers for screenshots. Nothing is written to your real fleet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("“Forever” is a perpetual license for the app as it is. It does not promise future updates, new features or support.")
        }
    }
}

/// The first section of Settings.
struct LicenseSettingsSection: View {
    @ObservedObject private var license = LicenseStore.shared

    var body: some View {
        Section {
            NavigationLink {
                LicenseView()
            } label: {
                LabeledContent {
                    Text(LicenseStatusSection.text(for: license.status))
                } label: {
                    Label("License", systemImage: "checkmark.seal")
                }
            }
            .accessibilityIdentifier("settings.license")
        }
    }
}
