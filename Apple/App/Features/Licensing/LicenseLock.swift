import SwiftUI

/// The sheet behind every locked tap.
struct LicenseLockSheet: View {
    let reason: LicenseGate.Reason
    @ObservedObject private var license = LicenseStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LicenseView(reason: reason)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
        .onChange(of: license.status.isActive) { _, active in
            if active { dismiss() }
        }
    }
}

/// Greys out a screen; taps open the lock sheet.
struct LicenseLockedModifier: ViewModifier {
    let exceptDemo: Bool
    @ObservedObject private var license = LicenseStore.shared
    @AppStorage(DemoServer.enabledKey) private var demoFleet = true

    func body(content: Content) -> some View {
        if license.status.isActive || (exceptDemo && demoFleet) {
            content
        } else {
            content
                .disabled(true)
                .blur(radius: 2)
                .overlay { LockCard(reason: LicenseGate.reason) }
        }
    }
}

/// Lock message with a buy button; opens its own sheet.
struct LockCard: View {
    let reason: LicenseGate.Reason
    @State private var asking: LicenseGate.Reason?

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { asking = reason }
            VStack(spacing: 12) {
                Image(systemName: "lock.fill").font(.largeTitle)
                Text(LicenseGate.message(for: reason)).font(.headline)
                Button {
                    asking = reason
                } label: {
                    Text(reason == .unlock ? "Buy" : "Activate")
                }
                .prominentActionButtonStyle()
                .accessibilityIdentifier("license.lock.buy")
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .licenseAsk($asking)
    }
}

/// Lock sheet for taps inside another sheet.
struct LicenseAskModifier: ViewModifier {
    @Binding var reason: LicenseGate.Reason?

    func body(content: Content) -> some View {
        content.sheet(item: $reason) { LicenseLockSheet(reason: $0) }
    }
}

/// Presents the lock sheet and the Mac approval sheet.
struct LicensePromptHost: ViewModifier {
    @ObservedObject private var prompt = LicensePrompt.shared
    @ObservedObject private var approval = PairApproval.shared

    func body(content: Content) -> some View {
        content
            .sheet(item: $prompt.reason) { reason in
                LicenseLockSheet(reason: reason)
            }
            .sheet(isPresented: Binding(get: { approval.nonce != nil },
                                        set: { if !$0 { approval.nonce = nil } })) {
                PairApprovalSheet()
            }
    }
}

extension View {
    func licenseLocked(exceptDemo: Bool = false) -> some View {
        modifier(LicenseLockedModifier(exceptDemo: exceptDemo))
    }
    func licensePromptHost() -> some View { modifier(LicensePromptHost()) }
    func licenseAsk(_ reason: Binding<LicenseGate.Reason?>) -> some View {
        modifier(LicenseAskModifier(reason: reason))
    }
}
