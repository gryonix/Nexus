import Foundation
import UserNotifications
#if os(iOS) || os(tvOS)
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
        #if os(iOS) || os(tvOS)
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
            #if os(iOS) || os(tvOS)
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

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        let gnx = notification.request.content.userInfo["gnx"] as? [String: Any]
        let options: UNNotificationPresentationOptions = Self.isRunReport(gnx) ? [.list] : [.banner, .list, .sound]
        DispatchQueue.main.async { completionHandler(options) }
    }

    /// A run start or end the open app already shows
    static func isRunReport(_ gnx: [String: Any]?) -> Bool {
        (gnx?["kind"] as? String)?.hasPrefix("gnx.alert.operation") == true
    }

    #if !os(tvOS)
    /// UIKit takes the completion only on the main thread
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let info = content.userInfo
        let actionIdentifier = response.actionIdentifier
        let (title, body) = (content.title, content.body)
        Task {
            await Self.handle(info["gnx"] as? [String: Any], actionIdentifier: actionIdentifier, title: title, body: body)
            DispatchQueue.main.async { completionHandler() }
        }
    }
    #endif

    private static func open(_ destination: AlertDestination?, card: AlertCard?) async {
        guard let destination else { return }
        if let card {
            await AppNavigator.shared.openServer(destination.deploymentID, at: destination.tab, showing: card)
        } else {
            await AppNavigator.shared.openServer(destination.deploymentID, at: destination.tab, service: destination.service)
        }
    }

    private static func handle(_ gnx: [String: Any]?, actionIdentifier: String, title: String, body: String) async {
        guard let gnx else { return }
        if let action = AlertAction(action: actionIdentifier, gnx: gnx) {
            await AlertActions.perform(action)
            return
        }
        switch AlertTap(gnx: gnx, title: title, body: body) {
        case .run(let jobID, let fallback, let card):
            if await RunningJobsWatcher.shared.open(jobID: jobID, on: fallback?.deploymentID) { return }
            await open(fallback, card: card)
        case .card(let destination, let card):
            await open(destination, card: card)
        case .server(let destination):
            await open(destination, card: nil)
        case .nothing:
            break
        }
    }
}

#if os(iOS) || os(tvOS)
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = ForegroundNotifications.shared
        #if !os(tvOS)
        UNUserNotificationCenter.current().setNotificationCategories(AlertActions.categories())
        #endif
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

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void) {
        completion(WidgetPush.received(userInfo) ? .newData : .noData)
    }
}
#else
final class PushAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            DockPresence.note("will finish launching")
            // Adds the Dock icon before any window appears
            MenuBarSettings.shared.applyActivationPolicy(activating: !LaunchSettings.shared.startsInBackground)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            DockPresence.shared.start()
            // Creates the store before the launch connect
            _ = LicenseStore.shared
            LaunchSettings.shared.applyAtLaunch()
            DockPresence.note("did finish launching")
        }
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
