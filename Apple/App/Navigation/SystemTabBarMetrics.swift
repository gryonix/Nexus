#if os(iOS)
import SwiftUI
import UIKit

enum SystemTabBarMetrics {
    static let fallback: CGFloat = 49

    static let breathingRoom: CGFloat = 8

    static func clearance() -> CGFloat {
        guard let window = keyWindow else { return fallback + breathingRoom }
        guard let bar = tabBar(in: window) else { return 0 }
        let top = bar.convert(bar.bounds, to: window).minY
        let overlap = window.bounds.maxY - top - window.safeAreaInsets.bottom
        guard overlap > 0 else { return 0 }
        return overlap + breathingRoom
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    private static func tabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        for subview in view.subviews {
            if let bar = tabBar(in: subview) { return bar }
        }
        return nil
    }
}

struct SystemBarClearance: ViewModifier {
    @State private var clearance = SystemTabBarMetrics.fallback + SystemTabBarMetrics.breathingRoom

    func body(content: Content) -> some View {
        content
            .bottomBarClearanceEverywhere()
            .environment(\.barClearance, clearance)
            .task { await measure() }
            .onReceive(NotificationCenter.default.publisher(
                for: UIDevice.orientationDidChangeNotification)) { _ in
                Task { await measure() }
            }
    }

    @MainActor
    private func measure() async {
        for _ in 0..<10 {
            let measured = SystemTabBarMetrics.clearance()
            if measured > 0 {
                clearance = measured
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
#endif
