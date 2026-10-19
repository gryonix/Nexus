import CoreImage.CIFilterBuiltins
import SwiftUI

/// Mac outside the App Store: QR code for an iPhone.
struct MacPairingView: View {
    @State private var link: String?
    @State private var failure: String?
    @State private var done = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Scan this code with the camera of an iPhone that has bought gryonixNexus.")
                .multilineTextAlignment(.center)
            if let link, let image = QRCode.image(for: link) {
                image.interpolation(.none).resizable().frame(width: 220, height: 220)
            } else if failure == nil {
                ProgressView()
            }
            if done { Label("This Mac is activated.", systemImage: "checkmark.seal.fill") }
            if let failure { Text(failure).foregroundStyle(.red) }
        }
        .padding()
        .navigationTitle(Text("Restore with iPhone"))
        .task { await pair() }
    }

    private func pair() async {
        do {
            let nonce = try await LicenseAPI.startPairing()
            link = PairApproval.link(nonce: nonce)
            for _ in 0..<200 {
                try await Task.sleep(for: .seconds(3))
                if let grant = try? await LicenseAPI.pollPairing(nonce: nonce) {
                    try LicenseStore.shared.apply(grant)
                    done = true
                    return
                }
            }
        } catch {
            failure = error.localizedDescription
        }
    }
}

enum QRCode {
    static func image(for text: String) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }
}

/// An iPhone approving a Mac from a scanned link.
@MainActor
final class PairApproval: ObservableObject {
    static let shared = PairApproval()
    @Published var nonce: String?
    @Published var failure: String?
    @Published var isWorking = false

    private init() {}

    nonisolated static func link(nonce: String) -> String {
        "gryonixnexus://pair?nonce=\(nonce)"
    }

    func handle(_ url: URL) -> Bool {
        guard url.scheme == "gryonixnexus", url.host == "pair",
              let nonce = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "nonce" })?.value else { return false }
        failure = nil
        self.nonce = nonce
        return true
    }

    func approve() async {
        guard let nonce else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let code = try await PurchaseStore.shared.codeForOtherDevices()
            try await LicenseAPI.approvePairing(nonce: nonce, code: code)
            self.nonce = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

struct PairApprovalSheet: View {
    @ObservedObject private var approval = PairApproval.shared

    var body: some View {
        NavigationStack {
            CardList {
                Section {
                    Text("Activate gryonixNexus on your Mac with this license? It takes one of your five devices.")
                    Button("Activate the Mac") { Task { await approval.approve() } }
                        .disabled(approval.isWorking)
                    if let failure = approval.failure { Text(failure).foregroundStyle(.red) }
                }
            }
            .navigationTitle(Text("Restore with iPhone"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { approval.nonce = nil }
                }
            }
        }
    }
}
