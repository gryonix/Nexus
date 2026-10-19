import Foundation
import ServerControl
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Every server learns this phone, independent of any open screen
@MainActor
final class NotifyFleetSync {
    static let shared = NotifyFleetSync()

    private var running: Task<Void, Never>?

    /// Fetches the push token when notifications are already allowed
    func refreshTokenIfAllowed() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        #if os(iOS)
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
        UIApplication.shared.registerForRemoteNotifications()
        #else
        guard [.authorized, .provisional].contains(settings.authorizationStatus) else { return }
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    /// Syncs every agent server once, one after another
    func syncAll() {
        guard running == nil else { return }
        running = Task { @MainActor in
            defer { running = nil }
            guard #available(macOS 15.0, *) else { return }
            let deployments = (try? FileDeploymentStore().load()) ?? []
            for deployment in deployments where deployment.usesAgent {
                await DashboardViewModel(deployment: deployment).syncNotifyPreferences()
            }
        }
    }
}
