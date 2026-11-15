@testable import gryonixNexus
import XCTest

final class NotifySoundsTests: XCTestCase {
    func testOnlySoundsOtherThanTheSystemsAreSent() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NotifySoundsTests"))
        defaults.removePersistentDomain(forName: "NotifySoundsTests")
        defaults.set("chime", forKey: NotifySounds.key(.backups))
        defaults.set("default", forKey: NotifySounds.key(.disks))
        defaults.set("none", forKey: NotifySounds.key(.ssh))
        XCTAssertEqual(NotifySounds.chosen(defaults), ["backups": "chime", "ssh": "none"])
        XCTAssertEqual(NotifySounds.fingerprint(defaults), "backups=chime,ssh=none")
    }

    func testEveryCarriedSoundIsInTheBundle() {
        for sound in NotifySound.allCases where ![.standard, .none].contains(sound) {
            XCTAssertNotNil(Bundle.main.url(forResource: sound.rawValue, withExtension: "wav"), sound.rawValue)
        }
    }
}
