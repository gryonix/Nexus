#if os(iOS)
import SwiftUI
import UIKit

/// The system bar's tabs slide sideways when switched
struct SystemTabSlide<Selection: Equatable>: ViewModifier {
    let selection: Selection

    func body(content: Content) -> some View {
        content
            .task {
                for _ in 0..<40 {
                    if TabSlideDelegate.install() { return }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            .onChange(of: selection) { TabSlideDelegate.install() }
    }
}

/// Keeps the controller's own delegate and adds the slide
@MainActor
final class TabSlideDelegate: NSObject, UITabBarControllerDelegate {
    private enum Key { nonisolated(unsafe) static var slide: UInt8 = 0 }

    private let original: UITabBarControllerDelegate?

    private init(original: UITabBarControllerDelegate?) {
        self.original = original
    }

    @discardableResult
    static func install() -> Bool {
        guard let controller = tabBarController() else { return false }
        if controller.delegate is TabSlideDelegate { return true }
        let slide = TabSlideDelegate(original: controller.delegate)
        objc_setAssociatedObject(controller, &Key.slide, slide, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        controller.delegate = slide
        return true
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }

    func tabBarController(_ controller: UITabBarController,
                          animationControllerForTransitionFrom from: UIViewController,
                          to: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let order = Self.pages(of: controller)
        guard let start = order.firstIndex(where: { $0 === from }),
              let end = order.firstIndex(where: { $0 === to }), start != end else { return nil }
        return TabSlideAnimator(forward: end > start)
    }

    private static func pages(of controller: UITabBarController) -> [UIViewController] {
        if let pages = controller.viewControllers, !pages.isEmpty { return pages }
        if #available(iOS 18.0, *) { return controller.tabs.compactMap(\.viewController) }
        return []
    }

    private static func tabBarController() -> UITabBarController? {
        let roots = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .compactMap(\.rootViewController)
        var queue = roots
        while !queue.isEmpty {
            let controller = queue.removeFirst()
            if let tabs = controller as? UITabBarController { return tabs }
            queue.append(contentsOf: controller.children)
        }
        return nil
    }
}

/// Old page slides out as the new one slides in
final class TabSlideAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let forward: Bool

    init(forward: Bool) { self.forward = forward }

    func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.38 * SlideSpeed.factor
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let from = context.view(forKey: .from), let to = context.view(forKey: .to),
              let incoming = context.viewController(forKey: .to) else {
            context.completeTransition(!context.transitionWasCancelled)
            return
        }
        let shift = forward ? context.containerView.bounds.width : -context.containerView.bounds.width
        to.frame = context.finalFrame(for: incoming)
        context.containerView.addSubview(to)
        to.transform = CGAffineTransform(translationX: shift, y: 0)
        let motion = UIViewPropertyAnimator(duration: transitionDuration(using: context), dampingRatio: 1)
        motion.addAnimations {
            from.transform = CGAffineTransform(translationX: -shift, y: 0)
            to.transform = .identity
        }
        motion.addCompletion { _ in
            #if DEBUG
            FrameProbe.note("slide end")
            #endif
            from.transform = .identity
            to.transform = .identity
            context.completeTransition(!context.transitionWasCancelled)
        }
        #if DEBUG
        FrameProbe.note("slide start")
        #endif
        motion.startAnimation()
    }
}
#endif
