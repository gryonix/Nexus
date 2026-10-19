import XCTest
@testable import ServerControl

final class TransferSealTests: XCTestCase {
    private let plain = Data(#"{"deployment":"x"}"#.utf8)

    func testARoundTripNeedsTheSamePassphrase() throws {
        let sealed = try TransferSeal.seal(plain, passphrase: "correct horse")
        XCTAssertTrue(TransferSeal.isSealed(sealed))
        XCTAssertFalse(TransferSeal.isSealed(plain))
        XCTAssertEqual(try TransferSeal.open(sealed, passphrase: "correct horse"), plain)
        XCTAssertThrowsError(try TransferSeal.open(sealed, passphrase: "wrong")) {
            XCTAssertEqual($0 as? TransferSeal.Failure, .wrongPassphrase)
        }
    }

    func testTheSealedFileCarriesNoPlaintext() throws {
        let sealed = try TransferSeal.seal(plain, passphrase: "p")
        XCTAssertNil(String(data: sealed, encoding: .utf8)?.range(of: "deployment"))
    }

    /// Made with Python cryptography; Android opens it too
    static let vector = #"{"ciphertext":"YtZyqfGCtfSalFk7MDRWgQKi1GAWtsOd5ERDwY9ESjtPo8sbaZ9tGg==","iterations":600000,"kdf":"pbkdf2-sha256","nonce":"ZGVmZ2hpamtsbW5v","salt":"AAECAwQFBgcICQoLDA0ODw==","type":"gryonixserver-sealed","version":1}"#

    func testAnIndependentlyMadeFileOpens() throws {
        XCTAssertEqual(try TransferSeal.open(Data(Self.vector.utf8), passphrase: "correct horse battery"),
                       Data(#"{"hello":"Привет"}"#.utf8))
    }

    func testFixedInputsSealToTheSameBytes() throws {
        let sealed = try TransferSeal.seal(Data(#"{"hello":"Привет"}"#.utf8), passphrase: "correct horse battery",
                                           salt: Data(0..<16), nonce: Data(100..<112))
        XCTAssertEqual(String(data: sealed, encoding: .utf8), Self.vector)
    }
}
