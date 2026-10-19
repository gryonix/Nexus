import SwiftUI
import XCTest

@testable import gryonixNexus

@MainActor
final class ActivityBannerWidthTests: XCTestCase {
    private let offeredWidths: [CGFloat] = [240, 280, 320, 350, 390, 400, 430, 500, 700]

    override func setUp() {
        super.setUp()
        clearRegistry()
    }

    override func tearDown() {
        clearRegistry()
        restorePending()
        super.tearDown()
    }

    private var savedPending: Data?

    private func clearRegistry() {
        let registry = RunningOperationsRegistry.shared
        registry.dismissPresented()
        for entry in registry.entries {
            entry.state.isFinished = true
            registry.dismiss(entry.id)
        }
        savedPending = UserDefaults.standard.data(forKey: InstallJobStore.key)
        UserDefaults.standard.removeObject(forKey: InstallJobStore.key)
        PendingAgentInstalls.shared.refresh()
    }

    private func restorePending() {
        if let savedPending {
            UserDefaults.standard.set(savedPending, forKey: InstallJobStore.key)
        } else {
            UserDefaults.standard.removeObject(forKey: InstallJobStore.key)
        }
        PendingAgentInstalls.shared.refresh()
    }

    private func presentLongOperation() {
        let state = LongOperationState(
            title: "Installing docker-mailserver and its certificate sync",
            progressText: "Waiting for the container to answer on 127.0.0.1:8080 before continuing")
        RunningOperationsRegistry.shared.start(state)
        RunningOperationsRegistry.shared.dismissPresented()
    }

    private func idealWidth(at offered: CGFloat) -> CGFloat {
        let host = UIHostingController(rootView: ActivityBanner())
        host.view.frame = CGRect(x: 0, y: 0, width: offered, height: 200)
        let size = host.sizeThatFits(in: CGSize(width: offered,
                                                height: CGFloat.greatestFiniteMagnitude))
        return size.width
    }

    /// The one that matters: at every width, the strip fits
    func testTheStripNeverAsksForMoreWidthThanItIsOffered() {
        presentLongOperation()
        for width in offeredWidths {
            let ideal = idealWidth(at: width)
            XCTAssertLessThanOrEqual(
                ideal, width + 0.5,
                "at \(width)pt the strip wants \(ideal)pt — it would be drawn past the tab bar's edge")
        }
    }

    func testTheMeasurementCanActuallyCatchSomethingTooWide() {
        let rigid = UIHostingController(
            rootView: Text(verbatim: String(repeating: "wide ", count: 40))
                .fixedSize(horizontal: true, vertical: false))
        let size = rigid.sizeThatFits(in: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertGreaterThan(size.width, 320,
                             "the harness must be able to see a view that overflows its offer")
    }

    func testTheStripHasHeightWhileSomethingIsRunning() {
        presentLongOperation()
        let host = UIHostingController(rootView: ActivityBanner())
        let size = host.sizeThatFits(in: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertGreaterThan(size.height, 30, "the strip drew nothing, so its width proves nothing")
    }

    func testAnIdleStripDrawsNothing() {
        XCTAssertEqual(RunningOperationsRegistry.shared.entries.count, 0, "operations")
        XCTAssertEqual(InstallSessionRegistry.shared.installing.count, 0, "installs")
        XCTAssertEqual(PendingAgentInstalls.shared.pending.count, 0, "pending")
        let idle = UIHostingController(rootView: ActivityBanner())
            .sizeThatFits(in: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertEqual(idle.height, 0, accuracy: 0.5,
                       "an idle strip must take no height at all, or the accessory slot "
                           + "reserves a blank plate above the tab bar for ever")
    }
}
