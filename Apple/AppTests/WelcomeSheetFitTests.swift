import SwiftUI
import XCTest

@testable import gryonixNexus

@MainActor
final class WelcomeSheetFitTests: XCTestCase {
    private let phones: [(name: String, width: CGFloat, height: CGFloat)] = [
        ("6.1\"", 390, 844),
        ("6.7\"", 428, 926),
        ("6.9\"", 440, 956),
    ]

    /// What the sheet does NOT get to use
    private static let sheetTopInset: CGFloat = 63
    private static let closeBarRow: CGFloat = 56
    private static let homeIndicator: CGFloat = 34

    private func available(_ height: CGFloat) -> CGFloat {
        height - Self.sheetTopInset - Self.closeBarRow - Self.homeIndicator
    }

    private func contentHeight(width: CGFloat) -> CGFloat {
        let host = UIHostingController(
            rootView: WelcomeContent(onConfigure: {}, onDismiss: {}))
        return host.sizeThatFits(
            in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    func testTheWelcomeFitsWithoutScrolling() {
        for phone in phones {
            let height = contentHeight(width: phone.width)
            XCTAssertGreaterThan(height, 300,
                                 "\(phone.name): the sheet drew almost nothing, so this proves nothing")
            XCTAssertLessThanOrEqual(
                height, available(phone.height),
                "\(phone.name): the welcome wants \(height)pt of "
                    + "\(available(phone.height))pt and scrolls")
        }
    }
}
