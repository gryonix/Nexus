import XCTest
@testable import AIAssistant

final class RedactorTests: XCTestCase {
    private func gone(_ input: String, _ secret: String, line: UInt = #line) {
        let out = Redactor.redact(input)
        XCTAssertFalse(out.contains(secret), out, line: line)
        XCTAssertTrue(out.contains("[REDACTED"), out, line: line)
    }

    func testPasswordAssignments() {
        gone("password=hunter2xyz", "hunter2xyz")
        gone("DB_PASSWORD: s3cr3t!", "s3cr3t!")
        gone("{\"password\": \"correct horse\"}", "correct horse")
        gone("passwd = 'abc 123'", "abc 123")
    }

    func testKeyValueNames() {
        gone("API_KEY=abcd1234", "abcd1234")
        gone("export SECRET_TOKEN=zzz999", "zzz999")
        gone("client-secret: top", "top")
        gone("key=value1", "value1")
        gone("SSH_KEY=material", "material")
    }

    func testKeepsInnocentWords() {
        XCTAssertEqual(Redactor.redact("monkey=3 and keyboard=on"), "monkey=3 and keyboard=on")
        XCTAssertEqual(Redactor.redact("authorization failed for user"), "authorization failed for user")
        XCTAssertEqual(Redactor.redact("PATH=/usr/bin:/bin"), "PATH=/usr/bin:/bin")
    }

    func testAuthorizationHeaders() {
        gone("Authorization: Bearer abc.def.ghi", "abc.def.ghi")
        gone("authorization: Basic dXNlcjpwYXNz", "dXNlcjpwYXNz")
        gone("curl -H 'Authorization: token ghp_abc'", "ghp_abc")
        gone("Proxy-Authorization: Basic cXdlcg==", "cXdlcg==")
    }

    func testBareBearer() {
        gone("sent Bearer 1234567890abcdef today", "1234567890abcdef")
    }

    func testJWT() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.c2lnbmF0dXJl"
        gone("session \(jwt) ok", jwt)
    }

    func testPrivateKeyBlock() {
        let block = "-----BEGIN OPENSSH PRIVATE KEY-----\nAAAAB3Nz\nline2\n-----END OPENSSH PRIVATE KEY-----"
        let out = Redactor.redact("before\n\(block)\nafter")
        XCTAssertEqual(out, "before\n[REDACTED PRIVATE KEY]\nafter")
    }

    func testUnterminatedPrivateKey() {
        let out = Redactor.redact("x\n-----BEGIN RSA PRIVATE KEY-----\nMIIE")
        XCTAssertFalse(out.contains("MIIE"))
    }

    func testLongHexAndBase64() {
        let hex = String(repeating: "ab12", count: 8)
        gone("id \(hex) up", hex)
        let b64 = "Zm9vYmFyMTIzNDU2Nzg5MGFiY2RlZmdoaWprbG1ub3A="
        gone("blob \(b64)", b64)
    }

    func testShortTokensAndPlainLongWordsStay() {
        XCTAssertEqual(Redactor.redact("abcdef0123456789"), "abcdef0123456789")
        let word = String(repeating: "a", count: 40)
        XCTAssertEqual(Redactor.redact(word), word)
    }

    func testUrlCredentials() {
        gone("postgres://admin:pw123@db:5432/x", "pw123")
    }

    func testCommandLineFlags() {
        gone("mysql --password hunter22 -h db", "hunter22")
        gone("tool --token=abc12345", "abc12345")
    }

    func testIdempotent() {
        let once = Redactor.redact("password=abc token: xyz Authorization: Bearer q1w2e3r4")
        XCTAssertEqual(Redactor.redact(once), once)
    }

    func testMultilineKeepsOtherLines() {
        let out = Redactor.redact("line one\nTOKEN=abc\nline three")
        XCTAssertEqual(out, "line one\nTOKEN=[REDACTED]\nline three")
    }
}
