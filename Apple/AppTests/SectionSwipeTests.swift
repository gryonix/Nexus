#if os(iOS)
import UIKit
import XCTest

@testable import gryonixNexus

@MainActor
final class SectionSwipeTests: XCTestCase {
    private func screenWithRider() -> (UINavigationController, SectionSwipe.Rider, SectionSwipe.Coordinator) {
        let coordinator = SectionSwipe.Coordinator(onSwipe: { _ in })
        let page = UIViewController()
        let stack = UINavigationController(rootViewController: page)
        let window = Self.window()
        window.rootViewController = stack
        window.isHidden = false
        window.layoutIfNeeded()
        let container = UIView(frame: page.view.bounds)
        page.view.addSubview(container)
        let rider = SectionSwipe.Rider(coordinator: coordinator)
        container.addSubview(rider)
        return (stack, rider, coordinator)
    }

    /// A window on the running app's scene
    private static func window() -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844)) }
        return UIWindow(windowScene: scene)
    }

    private func pans(on stack: UINavigationController) -> [UIGestureRecognizer] {
        (stack.view.gestureRecognizers ?? []).filter { $0 is SectionSwipe.Pan }
    }

    func testTheScreenCarriesOneRecogniserHoweverOftenItIsAttached() {
        let (stack, rider, _) = screenWithRider()
        XCTAssertNotNil(rider.window, "the rider is not in a window — nothing would attach")
        for _ in 0..<5 { rider.attach() }
        XCTAssertEqual(pans(on: stack).count, 1,
                       "the navigation view is shared by every screen in the stack — a second "
                       + "recogniser on it reports the same flick twice and moves two sections")
    }

    func testARebuiltPageReplacesItsOwnRecogniserInsteadOfAddingOne() {
        let (stack, rider, coordinator) = screenWithRider()
        rider.attach()
        let second = SectionSwipe.Rider(coordinator: coordinator)
        rider.superview?.addSubview(second)
        second.attach()
        XCTAssertEqual(pans(on: stack).count, 1,
                       "the page was rebuilt and left its old recogniser behind")
    }

    func testAFlickIsReportedOnceEvenWhenTwoRecognisersSawIt() {
        let coordinator = SectionSwipe.Coordinator(onSwipe: { _ in })
        let moment = Date()
        let travel = CGPoint(x: -120, y: 10)
        XCTAssertTrue(coordinator.accepts(travel: travel, at: moment))
        XCTAssertFalse(coordinator.accepts(travel: travel, at: moment.addingTimeInterval(0.05)),
                       "the same flick moved the page twice")
        XCTAssertTrue(
            coordinator.accepts(travel: travel,
                                at: moment.addingTimeInterval(SectionSwipe.Coordinator.quietAfterSwipe + 0.01)),
            "a swipe made after the quiet time is a swipe of its own")
    }

    func testASlowDragIsLetThroughAndAFastScrollIsNot() {
        let coordinator = SectionSwipe.Coordinator(onSwipe: { _ in })
        XCTAssertTrue(coordinator.begins(speed: CGPoint(x: 900, y: 40)),
                      "a quick flick sideways is what this gesture is for")
        XCTAssertFalse(coordinator.begins(speed: CGPoint(x: 40, y: 900)),
                       "a fast scroll down is the list's, not ours")
        XCTAssertTrue(coordinator.begins(speed: CGPoint(x: 18, y: 22)),
                      "a slow drag has no direction in its first samples — judging it there "
                      + "is how a real swipe gets refused")
    }

    func testWithNothingThatWayTheDragIsLeftToGoingBack() {
        let coordinator = SectionSwipe.Coordinator(onSwipe: { _ in })
        coordinator.canMove = { $0 < 0 }
        XCTAssertTrue(coordinator.leadsSomewhere(speed: CGPoint(x: -300, y: 0), travel: .zero),
                      "there is a next section, so the swipe is ours")
        XCTAssertFalse(coordinator.leadsSomewhere(speed: CGPoint(x: 300, y: 0), travel: .zero),
                       "on the first section a swipe right must go back to the list")
        XCTAssertFalse(coordinator.leadsSomewhere(speed: .zero, travel: CGPoint(x: 20, y: 0)),
                       "with no speed yet the travel so far tells the direction")
    }

    func testGoingBackWaitsForTheSwipeToDecline() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("no drag-anywhere back before iOS 26") }
        let (stack, rider, coordinator) = screenWithRider()
        rider.attach()
        let pan = try XCTUnwrap(pans(on: stack).first)
        let back = try XCTUnwrap(stack.interactiveContentPopGestureRecognizer)
        XCTAssertTrue(coordinator.gestureRecognizer(pan, shouldBeRequiredToFailBy: back),
                      "a swipe right between sections also left the server screen")
        XCTAssertFalse(coordinator.gestureRecognizer(pan, shouldRecognizeSimultaneouslyWith: back),
                       "moving a section and going back must not both happen")
    }

    func testAShortOrUprightTravelIsNotASwipe() {
        let coordinator = SectionSwipe.Coordinator(onSwipe: { _ in })
        XCTAssertFalse(coordinator.accepts(travel: CGPoint(x: -40, y: 2)),
                       "40 points sideways is a tap that slipped, not a swipe")
        XCTAssertFalse(coordinator.accepts(travel: CGPoint(x: -80, y: 70)),
                       "that is a scroll, and the list under it needs it")
    }
}
#endif
