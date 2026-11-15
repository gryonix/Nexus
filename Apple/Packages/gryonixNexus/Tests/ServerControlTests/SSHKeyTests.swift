import Foundation
import XCTest
@testable import ServerControl

final class SSHKeyTests: XCTestCase {
    private let ed25519 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAUMolS1zrD6Ge2IVa266sEAEprkKRu0lYVShpHUWitM test"
    private let ecdsa = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBBVDeILoz30CLxOBTtE7dmpT0qonP/29dri6/7C41teLkvEwzkyHCY6+0f9jyDjOWlEcSrKCgMdK1EnBkNiySZ0= test"

    func testEd25519FingerprintAndRandomartMatchOpenSSH() {
        XCTAssertEqual(SSHFingerprint.sha256(publicKeyLine: ed25519),
                       "SHA256:luP6EoiNAAte1PsxDv5/E4CNh1YSAK3Dw5d/Lq76cx4")
        let art = SSHFingerprint.randomArt(publicKeyLine: ed25519, kind: .ed25519)
        XCTAssertEqual(art, """
        +--[ED25519 256]--+
        |  .o+....        |
        |o  . o . .       |
        |+.+ . o B        |
        |o. * = B =       |
        | . +=.* S .      |
        |  o o..* o .     |
        |      .E+   .    |
        |     ..=.. o     |
        |   .ooB=+.. .    |
        +----[SHA256]-----+
        """)
    }

    func testEcdsaFingerprintAndRandomartMatchOpenSSH() {
        XCTAssertEqual(SSHFingerprint.sha256(publicKeyLine: ecdsa),
                       "SHA256:SNpaWEgF6TTeTiziByRxba56EDD+lZYKt+W0uo53RD0")
        let art = SSHFingerprint.randomArt(publicKeyLine: ecdsa, kind: .ecdsaP256)
        XCTAssertEqual(art?.split(separator: "\n").first, "+---[ECDSA 256]---+")
        XCTAssertTrue(art?.contains("|.oo.=#+E         |") ?? false)
    }

    func testGeneratedKeysHaveExpectedFormats() throws {
        for kind in [SSHKeyKind.ed25519, .ecdsaP256, .rsa3072] {
            let key = try SSHKeyGenerator.generate(kind: kind, name: "k")
            XCTAssertTrue(key.publicKey.hasPrefix(kind.algorithm + " AAAA"))
            XCTAssertTrue(key.fingerprint.hasPrefix("SHA256:"))
            XCTAssertTrue(key.privateKeyPEM.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----\n"))
            XCTAssertEqual(key.randomArt.split(separator: "\n").count, 11)
        }
    }

    #if os(macOS)
    func testSshKeygenAcceptsGeneratedPrivateKeys() throws {
        for kind in [SSHKeyKind.ed25519, .ecdsaP256, .rsa3072] {
            let key = try SSHKeyGenerator.generate(kind: kind, name: "k")
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try key.privateKeyPEM.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            defer { try? FileManager.default.removeItem(at: file) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            process.arguments = ["-y", "-f", file.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            let printed = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertEqual(process.terminationStatus, 0)
            let expected = key.publicKey.split(separator: " ").prefix(2).joined(separator: " ")
            XCTAssertTrue(printed.hasPrefix(expected), "\(kind)")
        }
    }
    #endif

    func testAuthorizedKeysCommandIsIdempotentAndSafe() throws {
        let command = try XCTUnwrap(AuthorizedKeysInstall.command(publicKeyLine: ed25519))
        XCTAssertTrue(command.contains("chmod 600"))
        XCTAssertTrue(command.contains("grep -qF"))
        XCTAssertTrue(command.contains(">> \"$HOME/.ssh/authorized_keys\""))
        XCTAssertNil(AuthorizedKeysInstall.command(publicKeyLine: "ssh-ed25519 x'; rm -rf / #"))
        XCTAssertNil(AuthorizedKeysInstall.command(publicKeyLine: "junk"))
    }

    func testAuthorizedKeysCommandRunsTwiceWithoutDuplicating() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let command = try XCTUnwrap(AuthorizedKeysInstall.command(publicKeyLine: ed25519))
        func run() throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }
        XCTAssertTrue(try run().contains(AuthorizedKeysInstall.added))
        XCTAssertTrue(try run().contains(AuthorizedKeysInstall.alreadyThere))
        let file = home.appendingPathComponent(".ssh/authorized_keys")
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(text.split(separator: "\n").count, 1)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    func testOutcomeParsing() {
        XCTAssertEqual(AuthorizedKeysInstall.outcome(of: ExecResult(exitCode: 0, stdout: "gryonix-key-added\n", stderr: "")), .added)
        XCTAssertEqual(AuthorizedKeysInstall.outcome(of: ExecResult(exitCode: 1, stdout: "", stderr: "x")), .failed)
    }
}
