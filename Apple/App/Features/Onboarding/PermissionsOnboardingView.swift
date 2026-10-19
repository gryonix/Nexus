import LocalAuthentication
import SwiftUI

/// First-launch screen asking for the permissions the app uses.
struct PermissionsOnboardingView: View {
    var onFinish: () -> Void

    @State private var localNetwork: PermissionState = .notAsked
    @State private var biometrics: PermissionState = BiometricPermission.currentState

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                OnboardingHeader()
                VStack(spacing: 12) {
                    localNetworkRow
                    if biometrics != .unavailable { biometricsRow }
                }
                OnboardingFooter(allDone: allDone, onFinish: onFinish)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(pageBackground.ignoresSafeArea())
    }

    private var pageBackground: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    private var allDone: Bool {
        localNetwork == .granted && [.granted, .unavailable].contains(biometrics)
    }

    private var localNetworkRow: some View {
        PermissionRow(symbol: "network", tint: .blue,
                      title: "Local Network",
                      detail: "Reach servers on your home network over SSH.",
                      state: localNetwork) {
            localNetwork = .asking
            localNetwork = await LocalNetworkPermission.request()
        }
    }

    private var biometricsRow: some View {
        PermissionRow(symbol: BiometricLabel.symbol, tint: .green,
                      title: BiometricLabel.title,
                      detail: "Protect saved passwords and server exports.",
                      state: biometrics) {
            biometrics = .asking
            biometrics = await BiometricPermission.request(
                reason: UIL10n.string("Protect saved passwords and server exports."))
        }
    }
}

private struct OnboardingHeader: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 24,
                                                                            style: .continuous))
            Text("Before you start")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("gryonixNexus needs a couple of permissions to manage your servers.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct OnboardingFooter: View {
    var allDone: Bool
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onFinish) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .prominentActionButtonStyle()
            .controlSize(.large)
            if !allDone {
                Button("Not now", action: onFinish)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One permission, its purpose and an ask button.
private struct PermissionRow: View {
    var symbol: String
    var tint: Color
    var title: LocalizedStringKey
    var detail: LocalizedStringKey
    var state: PermissionState
    var ask: () async -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            PermissionControl(state: state, ask: ask)
        }
        .padding(16)
        .glassCardBackground(fallback: GlassPalette.cardBase)
    }
}

private struct PermissionControl: View {
    var state: PermissionState
    var ask: () async -> Void

    var body: some View {
        switch state {
        case .notAsked:
            Button("Allow") { Task { await ask() } }
                .secondaryActionButtonStyle()
        case .asking:
            ProgressView()
        case .granted:
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(.green)
        case .denied:
            OpenSettingsButton()
        case .unavailable:
            EmptyView()
        }
    }
}

private struct OpenSettingsButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Open Settings") {
            #if os(iOS)
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            #else
            let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"
            if let url = URL(string: pane) { openURL(url) }
            #endif
        }
        .secondaryActionButtonStyle()
        .tint(.orange)
    }
}

private enum BiometricLabel {
    static var title: LocalizedStringKey {
        switch BiometricPermission.kind {
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Face ID"
        }
    }

    static var symbol: String {
        switch BiometricPermission.kind {
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "faceid"
        }
    }
}

/// Shows the permissions screen once, on first launch.
struct PermissionsOnboardingModifier: ViewModifier {
    static let shownKey = "onboarding.permissionsShown"

    @AppStorage(Self.shownKey) private var shown = false
    @State private var dismissed = false

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: presented) {
            PermissionsOnboardingView(onFinish: finish)
        }
        #else
        content.sheet(isPresented: presented) {
            PermissionsOnboardingView(onFinish: finish)
                .frame(minWidth: 480, minHeight: 560)
        }
        #endif
    }

    #if DEBUG
    /// `-resetFirstLaunch` starts the app as if newly installed.
    static func resetIfAsked() {
        guard CommandLine.arguments.contains("-resetFirstLaunch") else { return }
        UserDefaults.standard.removeObject(forKey: shownKey)
        UserDefaults.standard.removeObject(forKey: AppTour.shownKey)
        TabBarSettings.forgetBarStyles()
        WelcomeState.forget()
    }
    #endif

    private func finish() {
        shown = true
        dismissed = true
    }

    private var presented: Binding<Bool> {
        Binding(get: { !dismissed && (Self.forced || (!shown && Self.appliesHere)) },
                set: { if !$0 { finish() } })
    }

    private static var forced: Bool {
        ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_PERMISSIONS"] != nil
    }

    /// Kept out of automated runs, which set environment variables.
    static var appliesHere: Bool {
        #if DEBUG
        if CommandLine.arguments.contains("-resetFirstLaunch") { return true }
        #endif
        let environment = ProcessInfo.processInfo.environment
        return !environment.keys.contains { $0.hasPrefix("GRYONIXNEXUS_") }
            && environment["XCTestConfigurationFilePath"] == nil
    }
}

extension View {
    func permissionsOnboarding() -> some View {
        modifier(PermissionsOnboardingModifier())
    }
}
