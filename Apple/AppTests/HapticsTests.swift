import SwiftUI
import XCTest

@testable import gryonixNexus

@MainActor
final class HapticsTests: XCTestCase {
    private let key = Haptics.settingKey

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testOnlyADestructiveButtonFeelsHeavier() {
        XCTAssertEqual(Haptics.feel(forRole: .destructive), .weighty)
        XCTAssertEqual(Haptics.feel(forRole: nil), .tap)
        XCTAssertEqual(Haptics.feel(forRole: .cancel), .tap)
    }

    func testFeedbackIsOnUntilItIsTurnedOff() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(Haptics.isEnabled, "a fresh install should feel its buttons")

        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(Haptics.isEnabled)

        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(Haptics.isEnabled)
    }

    /// Playing with the setting off must not reach the engine
    func testPlayingIsInertWhileTheSettingIsOff() {
        UserDefaults.standard.set(false, forKey: key)
        Haptics.play(.tap)
        Haptics.play(.weighty)
        Haptics.play(.success)
        Haptics.play(.failure)
        XCTAssertFalse(Haptics.isEnabled)
    }
}
