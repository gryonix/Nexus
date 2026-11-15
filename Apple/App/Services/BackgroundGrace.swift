import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class BackgroundGrace {
    #if canImport(UIKit)
    private var id: UIBackgroundTaskIdentifier = .invalid

    /// `onExpire` runs just before iOS suspends the app
    init(onExpire: (@MainActor () -> Void)? = nil) {
        id = UIApplication.shared.beginBackgroundTask(withName: "gryonixnexus.install") { [weak self] in
            MainActor.assumeIsolated { onExpire?() }
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
    #else
    init(onExpire: (@MainActor () -> Void)? = nil) {}
    func end() {}
    #endif
}
