#if os(macOS)
import Combine
import Foundation
import Sparkle
import SwiftUI

@MainActor
final class AppUpdates: ObservableObject {
    static let shared = AppUpdates()

    private let controller: SPUStandardUpdaterController?

    /// Whether the button can do anything right now
    @Published private(set) var canCheck = false

    private init() {
        guard Self.isConfigured else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                      updaterDelegate: nil,
                                                      userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheck)
    }

    static var isConfigured: Bool {
        guard
            let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let url = URL(string: feed), url.scheme == "https",
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            !key.isEmpty, key != placeholderPublicKey
        else { return false }
        return true
    }

    static let placeholderPublicKey = "REPLACE_WITH_YOUR_SPARKLE_ED_PUBLIC_KEY"

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// The version the running app reports, for the row's subtitle
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

struct AppUpdateSection: View {
    @ObservedObject private var updates = AppUpdates.shared

    var body: some View {
        Section {
            Button {
                updates.checkForUpdates()
            } label: {
                Label("Check for updates", systemImage: "arrow.down.circle")
            }
            .disabled(!updates.canCheck)
        } header: {
            Text("Application")
        } footer: {
            if AppUpdates.isConfigured {
                Text("Version \(updates.currentVersion). Checks for a newer gryonixNexus and installs it after verifying its signature.")
            } else {
                Text("Version \(updates.currentVersion). Automatic updates are not set up in this build — it carries no update source or signing key.")
            }
        }
    }
}
#endif
