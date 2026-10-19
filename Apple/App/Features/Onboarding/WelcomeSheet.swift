import SwiftUI

/// What this app is, said once, on the first launch
struct WelcomeSheet: View {
    /// Opens the configurator
    let onConfigure: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        MacWelcomeView(onConfigure: {
            dismiss()
            onConfigure()
        }, onDismiss: { dismiss() })
        #else
        NavigationStack {
            ScrollView {
                WelcomeContent(onConfigure: {
                    dismiss()
                    onConfigure()
                }, onDismiss: { dismiss() })
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        #endif
    }
}

struct WelcomeContent: View {
    let onConfigure: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your own servers, set up for you")
                    .font(.largeTitle.bold())
                Text("gryonixNexus writes the configuration, installs it over SSH and then manages it — mail, files, photos, passwords, VPN. No account, no cloud, nothing of yours passes through anybody else.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                point("wand.and.stars", "It builds the server",
                      "Pick what you want to run. The app generates the whole configuration — Docker, TLS, firewall, DNS records — and installs it on a machine you own.")
                point("chart.bar.xaxis", "Then it watches it",
                      "Live CPU, memory, disk and traffic, backups on a schedule, updates with a rollback if the new image does not come up.")
                point("lock.shield", "And keeps it yours",
                      "Credentials live in this device's Keychain and on your server. There is no backend to trust, and no account to lose.")
            }

            VStack(spacing: 10) {
                Button(action: onConfigure) {
                    Text("Set up a server")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .prominentActionButtonStyle()
                .controlSize(.large)

                Button("Look around first", action: onDismiss)
                    .font(.callout)
            }
            Text("The servers you see behind this are examples, so every screen works before you own anything.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 20)
    }

    private func point(_ symbol: String, _ title: LocalizedStringKey,
                       _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// Whether the welcome has been shown
enum WelcomeState {
    private static let key = "welcome.shown"

    static var store: UserDefaults = .standard

    static var hasBeenShown: Bool { store.bool(forKey: key) }

    static func hasBeenShown(in defaults: UserDefaults) -> Bool { defaults.bool(forKey: key) }

    static func markShown() { store.set(true, forKey: key) }

    #if DEBUG
    static func forget() { store.removeObject(forKey: key) }
    #endif
}
