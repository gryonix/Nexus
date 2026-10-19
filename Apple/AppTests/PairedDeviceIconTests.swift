import XCTest

@testable import gryonixNexus

final class PairedDeviceIconTests: XCTestCase {
    func testApplePlatformsAreToldApart() {
        XCTAssertEqual(PairedDeviceIcon.symbol(for: "iPhone"), "iphone")
        XCTAssertEqual(PairedDeviceIcon.symbol(for: "Morgan's iPhone"), "iphone")
        XCTAssertEqual(PairedDeviceIcon.symbol(for: "iPad Pro"), "ipad")
        XCTAssertEqual(PairedDeviceIcon.symbol(for: "MacBook Pro"), "laptopcomputer")
        XCTAssertEqual(PairedDeviceIcon.symbol(for: "Mac mini"), "desktopcomputer")
    }

    func testAndroidPhonesAreReadAsPhones() {
        for label in ["Pixel 8", "SM-G991B", "Redmi Note 12", "OnePlus 11"] {
            XCTAssertEqual(PairedDeviceIcon.symbol(for: label), "smartphone", label)
        }
    }

    func testDesktopsAndLaptopsAreReadAsComputers() {
        XCTAssertEqual(PairedDeviceIcon.symbol(for: "ThinkPad X1"), "pc")
        XCTAssertEqual(PairedDeviceIcon.symbol(for: "Surface Laptop"), "pc")
    }

    func testAnUnreadableLabelDoesNotClaimAPhone() {
        XCTAssertEqual(PairedDeviceIcon.symbol(for: ""), PairedDeviceIcon.unknown)
        XCTAssertEqual(PairedDeviceIcon.symbol(for: "   "), PairedDeviceIcon.unknown)
        XCTAssertEqual(PairedDeviceIcon.symbol(for: "Работа"), PairedDeviceIcon.unknown)
    }
}
