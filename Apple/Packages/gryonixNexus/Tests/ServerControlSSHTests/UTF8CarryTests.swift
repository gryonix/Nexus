import NIOCore
import XCTest
@testable import ServerControlSSH

final class UTF8CarryTests: XCTestCase {
    func testACharacterSplitAcrossPacketsComesOutWhole() {
        let bytes = Array("Привет, мир — 你好 🙂".utf8)
        for cut in 1..<bytes.count {
            var carry = UTF8Carry()
            let first = carry.append(ByteBuffer(bytes: Array(bytes[..<cut])))
            let second = carry.append(ByteBuffer(bytes: Array(bytes[cut...])))
            XCTAssertEqual(first + second + carry.flush(), "Привет, мир — 你好 🙂", "cut at \(cut)")
        }
    }

    func testBytesThatNeverFormACharacterAreStillReturnedAtTheEnd() {
        var carry = UTF8Carry()
        XCTAssertEqual(carry.append(ByteBuffer(bytes: [0x61, 0xE4])), "a")
        XCTAssertEqual(carry.flush(), "\u{FFFD}")
    }
}
