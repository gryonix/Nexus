#if os(iOS)
import SwiftUI
import UIKit

/// Sideways across the page moves to the next section
struct SectionSwipe: UIViewRepresentable {
    /// Whether a section lies that way
    let canMove: (CGFloat) -> Bool
    let onSwipe: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView { Rider(coordinator: context.coordinator) }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onSwipe = onSwipe
        context.coordinator.canMove = canMove
        (view as? Rider)?.attach()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSwipe: onSwipe) }

    /// The recogniser this puts on a screen
    final class Pan: UIPanGestureRecognizer {
        weak var owner: Coordinator?
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// One flick reports once, however many recognisers saw it
        static let quietAfterSwipe: TimeInterval = 0.4

        var onSwipe: (CGFloat) -> Void
        var canMove: (CGFloat) -> Bool = { _ in true }
        /// The page this rides on
        weak var page: UIView?
        /// The screen the page belongs to
        weak var host: UIViewController?
        private var lastSwipe: Date?
        private var reportedThisTouch = false

        init(onSwipe: @escaping (CGFloat) -> Void) { self.onSwipe = onSwipe }

        @objc func handle(_ pan: UIPanGestureRecognizer) {
            if pan.state == .began { reportedThisTouch = false }
            guard pan.state == .changed || pan.state == .ended, !reportedThisTouch else { return }
            let travelled = pan.translation(in: pan.view)
            guard accepts(travel: travelled) else { return }
            reportedThisTouch = true
            onSwipe(travelled.x)
        }

        /// Sideways, far enough, and not a repeat
        func accepts(travel: CGPoint, at moment: Date = Date()) -> Bool {
            guard abs(travel.x) > abs(travel.y) * 1.6, abs(travel.x) > 60 else { return false }
            if let lastSwipe, moment.timeIntervalSince(lastSwipe) < Self.quietAfterSwipe {
                return false
            }
            lastSwipe = moment
            return true
        }

        func gestureRecognizerShouldBegin(_ recogniser: UIGestureRecognizer) -> Bool {
            guard let pan = recogniser as? UIPanGestureRecognizer, let page,
                  pageIsFrontmost else { return false }
            let speed = pan.velocity(in: pan.view)
            guard begins(speed: speed),
                  leadsSomewhere(speed: speed, travel: pan.translation(in: pan.view)) else { return false }
            return page.bounds.contains(pan.location(in: page))
        }

        /// No section that way leaves the drag to going back
        func leadsSomewhere(speed: CGPoint, travel: CGPoint) -> Bool {
            let heading = speed.x != 0 ? speed.x : travel.x
            return heading == 0 || canMove(heading)
        }

        /// A crawl has no direction yet
        func begins(speed: CGPoint) -> Bool {
            if abs(speed.x) + abs(speed.y) < Self.crawling { return true }
            return abs(speed.x) > abs(speed.y)
        }

        /// Points per second below which a drag says nothing
        static let crawling: CGFloat = 120

        /// The recogniser rides the whole stack
        private var pageIsFrontmost: Bool {
            guard let host, host.presentedViewController == nil else { return false }
            guard let stack = host.navigationController else { return true }
            return stack.topViewController === host
        }

        func gestureRecognizer(_ recogniser: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !isContentPop(other)
        }

        /// Going back waits until this swipe declines
        func gestureRecognizer(_ recogniser: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            isContentPop(other)
        }

        /// iOS 26 goes back from a drag anywhere
        private func isContentPop(_ other: UIGestureRecognizer) -> Bool {
            guard #available(iOS 26.0, *), let stack = host?.navigationController else { return false }
            return other === stack.interactiveContentPopGestureRecognizer
        }
    }

    /// Finds the screen's view once it is in the hierarchy
    final class Rider: UIView {
        private let coordinator: Coordinator
        private weak var carrying: UIView?
        private var pan: Pan?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not from a nib") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else {
                pan.map { carrying?.removeGestureRecognizer($0) }
                pan = nil
                carrying = nil
                return
            }
            attach()
        }

        func attach() {
            coordinator.page = superview ?? self
            coordinator.host = owningController()
            guard pan == nil, window != nil, let screen = owningScreen() else { return }
            Self.dropStale(on: screen, keeping: coordinator)
            let recogniser = Pan(target: coordinator, action: #selector(Coordinator.handle(_:)))
            recogniser.owner = coordinator
            recogniser.delegate = coordinator
            recogniser.cancelsTouchesInView = false
            recogniser.delaysTouchesBegan = false
            recogniser.delaysTouchesEnded = false
            screen.addGestureRecognizer(recogniser)
            carrying = screen
            pan = recogniser
        }

        /// An older twin on the shared screen doubles swipes
        static func dropStale(on screen: UIView, keeping coordinator: Coordinator) {
            for recogniser in screen.gestureRecognizers ?? [] {
                guard let pan = recogniser as? Pan else { continue }
                guard pan.owner == nil || pan.owner === coordinator else { continue }
                screen.removeGestureRecognizer(pan)
            }
        }

        private func owningScreen() -> UIView? {
            guard let host = owningController() else { return nil }
            return host.navigationController?.view ?? host.view
        }

        private func owningController() -> UIViewController? {
            var responder: UIResponder? = self
            while let next = responder, !(next is UIViewController) { responder = next.next }
            return responder as? UIViewController
        }
    }
}
#endif
