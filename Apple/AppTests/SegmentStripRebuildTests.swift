#if os(iOS)
import UIKit
import XCTest
@testable import gryonixNexus

final class SegmentStripRebuildTests: XCTestCase {
    private func items(vpnIcon: String) -> [StripItem] {
        [StripItem(id: "overview", title: "Overview", identifier: "o", iconName: "square.grid.2x2", showsTitle: false),
         StripItem(id: "settings", title: "Settings", identifier: "s", iconName: "slider.horizontal.3", showsTitle: false),
         StripItem(id: "vpn", title: "VPN", identifier: "v", iconName: vpnIcon, showsTitle: false)]
    }

    private func labels(in view: UIView) -> [UILabel] {
        view.subviews.flatMap { ($0 as? UILabel).map { [$0] } ?? labels(in: $0) }
    }

    /// A changed icon must not fly in during an animation
    func testRebuiltLabelsAppearInPlaceDuringAnAnimation() {
        let strip = SegmentStripView(frame: CGRect(x: 0, y: 0, width: 360, height: 44))
        strip.apply(items: items(vpnIcon: "TabIconGlobe"), selection: "overview")
        strip.layoutIfNeeded()
        UIView.animate(withDuration: 1) {
            strip.apply(items: self.items(vpnIcon: "TabIconLogo"), selection: "overview")
            strip.layoutIfNeeded()
        }
        let placed = labels(in: strip)
        XCTAssertFalse(placed.isEmpty, "the strip drew no labels — the test checks nothing")
        for label in placed {
            XCTAssertNotEqual(label.frame, .zero, "a label was left unplaced")
            XCTAssertEqual(label.layer.animationKeys() ?? [], [], "a rebuilt label animates into place")
        }
    }

    /// A new picture redraws the same labels, never new ones
    func testAChangedIconKeepsTheSameLabels() {
        let strip = SegmentStripView(frame: CGRect(x: 0, y: 0, width: 360, height: 44))
        strip.apply(items: items(vpnIcon: "TabIconGlobe"), selection: "overview")
        strip.layoutIfNeeded()
        let before = labels(in: strip).map(ObjectIdentifier.init)
        let frames = labels(in: strip).map(\.frame)
        strip.apply(items: items(vpnIcon: "TabIconLogo"), selection: "overview")
        strip.layoutIfNeeded()
        XCTAssertFalse(before.isEmpty, "the strip drew no labels — the test checks nothing")
        XCTAssertEqual(labels(in: strip).map(ObjectIdentifier.init), before, "the labels were rebuilt")
        XCTAssertEqual(labels(in: strip).map(\.frame), frames, "the labels moved")
    }
}
#endif
