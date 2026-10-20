import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// This device's push token from Apple
@MainActor
final class PushRegistration: ObservableObject {
    static let shared = PushRegistration()

    @Published private(set) var token: String?
    @Published private(set) var failure: String?
    private var waiters: [CheckedContinuation<String?, Never>] = []

    var platform: String { "apns" }

    /// What the server's list of devices calls this one
    static var deviceName: String {
        #if os(iOS)
        UIDevice.current.model
        #else
        Host.current().localizedName ?? "Mac"
        #endif
    }

    /// Asks for permission and a token; nil when refused
    func requestToken() async -> String? {
        if let token { return token }
        let allowed = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard allowed else {
            failure = UIL10n.string("Notifications are turned off for this app in the system settings.")
            return nil
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            #if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
            #else
            NSApplication.shared.registerForRemoteNotifications()
            #endif
        }
    }

    func received(_ data: Data) {
        let text = data.map { String(format: "%02x", $0) }.joined()
        let isNew = token != text
        token = text
        if isNew {
            NotifyFleetSync.shared.syncAll()
            #if os(iOS)
            Task { await LiveActivityStarts.shared.register() }
            #endif
        }
        failure = nil
        finish(text)
    }

    func failed(_ error: Error) {
        failure = error.localizedDescription
        finish(nil)
    }

    private func finish(_ value: String?) {
        waiters.forEach { $0.resume(returning: value) }
        waiters.removeAll()
    }
}

/// Shows notifications while the app is open
final class ForegroundNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundNotifications()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let gnx = info["gnx"] as? [String: Any] else { return }
        if let action = AlertAction(action: response.actionIdentifier, gnx: gnx) {
            await AlertActions.perform(action)
        } else if let jobID = gnx["job_id"] as? String {
            await RunningJobsWatcher.shared.follow(jobID: jobID)
        }
    }
}

#if os(iOS)
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = ForegroundNotifications.shared
        UNUserNotificationCenter.current().setNotificationCategories(AlertActions.categories())
        // Background launches have no screen to ask for the token
        Task { @MainActor in
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if status == .authorized || status == .provisional { application.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        Task { @MainActor in PushRegistration.shared.received(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushRegistration.shared.failed(error) }
    }
}
#else
final class PushAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in DockPresence.shared.start() }
        UNUserNotificationCenter.current().delegate = ForegroundNotifications.shared
        UNUserNotificationCenter.current().setNotificationCategories(AlertActions.categories())
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        Task { @MainActor in PushRegistration.shared.received(token) }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushRegistration.shared.failed(error) }
    }
}
#endif
