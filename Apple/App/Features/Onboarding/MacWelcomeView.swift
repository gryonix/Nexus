#if os(macOS)
import SwiftUI

/// The Mac's first screen
struct MacWelcomeView: View {
    let onConfigure: () -> Void
    let onDismiss: () -> Void

    /// The icon's colour, read once
    @State private var iconColour = AppIconChoice.current().colour

    var body: some View {
        HStack(spacing: 0) {
            hero
            content
        }
        .frame(width: 760)
        .frame(minHeight: 500)
    }

    // MARK: - The left panel

    private var hero: some View {
        ZStack {
            LinearGradient(colors: [iconColour.opacity(0.30), iconColour.opacity(0.08)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 18) {
                Spacer()
                icon
                Text(verbatim: "gryonixNexus")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .frame(width: 268)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.separator)
                .frame(width: 1)
        }
    }

    private var icon: some View {
        ZStack {
            layer("SplashLayerServer").foregroundStyle(iconColour)
            layer("SplashLayerHalo").foregroundStyle(Color.splashBackground)
            layer("SplashLayerGear").foregroundStyle(iconColour)
        }
        .frame(width: 172, height: 172)
    }

    private func layer(_ name: String) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }

    // MARK: - The right column

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your own servers, set up for you")
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text("gryonixNexus writes the configuration, installs it over SSH and then manages it — mail, files, photos, passwords, VPN. No account, no cloud, nothing of yours passes through anybody else.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 20) {
                point("wand.and.stars", "It builds the server",
                      "Pick what you want to run. The app generates the whole configuration — Docker, TLS, firewall, DNS records — and installs it on a machine you own.")
                point("chart.bar.xaxis", "Then it watches it",
                      "Live CPU, memory, disk and traffic, backups on a schedule, updates with a rollback if the new image does not come up.")
                point("lock.shield", "And keeps it yours",
                      "Credentials live in this device's Keychain and on your server. There is no backend to trust, and no account to lose.")
            }
            .padding(.top, 30)

            Spacer(minLength: 24)

            Text("The servers you see behind this are examples, so every screen works before you own anything.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            HStack(spacing: 12) {
                Button(action: onConfigure) {
                    Text("Set up a server")
                        .font(.headline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                }
                .prominentActionButtonStyle()
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button("Look around first", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func point(_ symbol: String, _ title: LocalizedStringKey,
                       _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    MacWelcomeView(onConfigure: {}, onDismiss: {})
}
#endif
