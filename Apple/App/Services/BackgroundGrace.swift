import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class BackgroundGrace {
    #if canImport(UIKit)
    private var id: UIBackgroundTaskIdentifier = .invalid

    init() {
        id = UIApplication.shared.beginBackgroundTask(withName: "gryonixnexus.install") { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
    #else
    init() {}
    func end() {}
    #endif
}
