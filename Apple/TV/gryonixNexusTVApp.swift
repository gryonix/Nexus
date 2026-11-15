import SwiftUI

/// The Apple TV app: system tabs, no keyboard
@main
struct gryonixNexusTVApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        TVStartup.prepare()
    }

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .tvLicenceGate()
                .tvKnockOverlay()
                .appAccentTint()
                .labelStyle(TVRowLabelStyle())
                .task { PurchaseStore.shared.start() }
                .task { TVLinkHostModel.shared.start() }
                .task { await TVStartup.keepSyncing() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { CloudSync.shared.scheduleSync(after: 0) }
                    if phase == .active { TVLinkHostModel.shared.resume() }
                    if phase == .background { TVLinkHostModel.shared.pause() }
                }
        }
    }
}

/// What the TV sets once at launch
@MainActor
enum TVStartup {
    static func prepare() {
        let environment = ProcessInfo.processInfo.environment
        if environment["GRYONIXNEXUS_DEMO_FLEET"] == nil {
            UserDefaults.standard.set(false, forKey: DemoServer.enabledKey)
        }
        if CloudSync.shared.mode == .off { CloudSync.shared.choose(.apple) }
    }

    /// iCloud has no push here: sync every few minutes
    static func keepSyncing() async {
        while !Task.isCancelled {
            await CloudSync.shared.sync()
            try? await Task.sleep(for: .seconds(300))
        }
    }
}
