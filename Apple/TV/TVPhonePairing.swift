import SwiftUI
import TVLink

/// The code a phone types to pair with this TV
struct TVPairingCodeCard: View {
    @ObservedObject private var link = TVLinkHostModel.shared

    var body: some View {
        VStack(spacing: 28) {
            Text(verbatim: link.code.description)
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("On your iPhone open Nexus › Settings › Apple TV, choose “\(link.tv.name)” and type this code.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 1000)
        }
    }
}

/// Pairing a phone, opened from the server list or Settings
struct TVPhonePairingSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 48) {
            Text("Pair an iPhone").font(.title.weight(.semibold))
            TVPairingCodeCard()
            Text("A paired iPhone keeps this Apple TV's license confirmed and can send it servers.")
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
        }
        .padding(80)
    }
}

/// Servers come from a paired phone; codes pair new ones
struct TVAddFromPhoneSheet: View {
    @ObservedObject private var link = TVLinkHostModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var pairingAnother = false

    var body: some View {
        if link.phones.isEmpty || pairingAnother {
            TVPhonePairingSheet()
        } else {
            VStack(spacing: 48) {
                Image(systemName: "iphone.and.arrow.forward").font(.system(size: 90))
                Text("Add from iPhone").font(.title.weight(.semibold))
                Text("On your iPhone open Nexus › Settings › Apple TV and choose “Send servers…” under this Apple TV.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 1100)
                Button("Pair another iPhone") { pairingAnother = true }
                Button("Done") { dismiss() }
            }
            .padding(80)
        }
    }
}

/// While a phone is pairing, its code fills the screen
struct TVKnockOverlay: ViewModifier {
    @ObservedObject private var link = TVLinkHostModel.shared
    @ObservedObject private var license = LicenseStore.shared

    /// The locked screen already shows the code
    private var covers: Bool { link.knocking != nil && license.status.isActive }

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: Binding(get: { covers }, set: { _ in })) {
            VStack(spacing: 40) {
                TVKnockTitle()
                TVPairingCodeCard()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
        }
    }
}

/// Names the phone that is pairing now
struct TVKnockTitle: View {
    @ObservedObject private var link = TVLinkHostModel.shared

    var body: some View {
        if let phone = link.knocking {
            Text("“\(phone.name)” wants to pair").font(.title2.weight(.semibold))
        }
    }
}
