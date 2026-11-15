import SwiftUI

/// Without a confirmed license the TV asks for the phone
struct TVLicenceGate: ViewModifier {
    @ObservedObject private var license = LicenseStore.shared
    @ObservedObject private var link = TVLinkHostModel.shared

    func body(content: Content) -> some View {
        if license.status.isActive {
            content.safeAreaInset(edge: .top) { reminder }
        } else {
            TVConnectPhoneScreen(hasPhones: !link.phones.isEmpty)
        }
    }

    @ViewBuilder private var reminder: some View {
        if let end = link.licenceEnds, end.timeIntervalSinceNow < 2 * 24 * 3600 {
            Label("Open Nexus on your iPhone to keep this Apple TV unlocked. Confirmed until \(end.formatted(date: .abbreviated, time: .shortened)).",
                  systemImage: "iphone.radiowaves.left.and.right")
                .font(.callout)
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(.orange.opacity(0.25))
        }
    }
}

struct TVConnectPhoneScreen: View {
    let hasPhones: Bool

    var body: some View {
        VStack(spacing: 48) {
            Image(systemName: "iphone.radiowaves.left.and.right").font(.system(size: 90))
            Text("Connect to your iPhone").font(.title.weight(.semibold))
            TVKnockTitle()
            if hasPhones {
                Text("This Apple TV checks your license through your iPhone. Open Nexus on the iPhone on the same network, and it confirms the license by itself.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 1100)
            }
            TVPairingCodeCard()
        }
        .padding(80)
    }
}

extension View {
    func tvLicenceGate() -> some View { modifier(TVLicenceGate()) }
    func tvKnockOverlay() -> some View { modifier(TVKnockOverlay()) }
}
