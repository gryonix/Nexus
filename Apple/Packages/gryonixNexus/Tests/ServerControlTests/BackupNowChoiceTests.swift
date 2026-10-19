import XCTest
@testable import ServerControl

final class BackupNowChoiceTests: XCTestCase {
    private let defaultsOn: Set<String> = ["vaultwarden", "mailcow"]
    private let always: Set<String> = ["vaultwarden"]

    func testServicesAreTickedAndUntickedInOrder() {
        var choice = BackupNowChoice()
        choice.toggle("nextcloud")
        choice.toggle("mailcow")
        choice.toggle("immich")
        choice.toggle("mailcow")
        XCTAssertEqual(choice.services, ["nextcloud", "immich"])
    }

    func testEncryptionFollowsTheChosenServicesUntilSet() {
        var choice = BackupNowChoice(services: ["nextcloud"])
        XCTAssertFalse(choice.encrypting(defaultsOn: defaultsOn))
        choice.toggle("mailcow")
        XCTAssertTrue(choice.encrypting(defaultsOn: defaultsOn))
        choice.encrypt = false
        XCTAssertFalse(choice.encrypting(defaultsOn: defaultsOn))
    }

    func testAnAlwaysEncryptedServiceNeedsAKeyEvenWithEncryptionOff() {
        let choice = BackupNowChoice(services: ["nextcloud", "vaultwarden"], encrypt: false)
        XCTAssertFalse(choice.encrypts("nextcloud", defaultsOn: defaultsOn, alwaysEncrypted: always))
        XCTAssertTrue(choice.encrypts("vaultwarden", defaultsOn: defaultsOn, alwaysEncrypted: always))
        XCTAssertTrue(choice.needsKey(defaultsOn: defaultsOn, alwaysEncrypted: always))
        let plain = BackupNowChoice(services: ["nextcloud"], encrypt: false)
        XCTAssertFalse(plain.needsKey(defaultsOn: defaultsOn, alwaysEncrypted: always))
    }

    func testTheStoredKeySendsNoPassword() {
        var choice = BackupNowChoice(services: ["mailcow"])
        choice.passphrase = "typed-but-unused"
        XCTAssertNil(choice.passphraseToSend)
        choice.key = .typed
        XCTAssertEqual(choice.passphraseToSend, "typed-but-unused")
    }

    func testReadiness() {
        var choice = BackupNowChoice()
        XCTAssertFalse(choice.isReady(defaultsOn: defaultsOn, alwaysEncrypted: always, hasStoredKey: true),
                       "nothing chosen")
        choice.toggle("mailcow")
        XCTAssertTrue(choice.isReady(defaultsOn: defaultsOn, alwaysEncrypted: always, hasStoredKey: true))
        XCTAssertTrue(choice.isReady(defaultsOn: defaultsOn, alwaysEncrypted: always, hasStoredKey: nil),
                      "an unknown key is tried; the server says if it is missing")
        XCTAssertFalse(choice.isReady(defaultsOn: defaultsOn, alwaysEncrypted: always, hasStoredKey: false))
        choice.key = .typed
        choice.passphrase = "longenough"
        choice.confirmation = "different!"
        XCTAssertFalse(choice.isReady(defaultsOn: defaultsOn, alwaysEncrypted: always, hasStoredKey: false))
        choice.confirmation = "longenough"
        XCTAssertTrue(choice.isReady(defaultsOn: defaultsOn, alwaysEncrypted: always, hasStoredKey: false))
        choice.passphrase = "short"
        choice.confirmation = "short"
        XCTAssertFalse(choice.isReady(defaultsOn: defaultsOn, alwaysEncrypted: always, hasStoredKey: false))
        let plain = BackupNowChoice(services: ["nextcloud"], encrypt: false)
        XCTAssertTrue(plain.isReady(defaultsOn: defaultsOn, alwaysEncrypted: always, hasStoredKey: false))
    }

    func testSizesAddUpAgainstTheTightestFreeSpace() {
        XCTAssertNil(BackupNowChoice.total([]))
        let total = BackupNowChoice.total([BackupEstimate(dataBytes: 10, freeBytes: 100),
                                           BackupEstimate(dataBytes: 30, freeBytes: 90)])
        XCTAssertEqual(total, BackupEstimate(dataBytes: 40, freeBytes: 90))
    }
}
