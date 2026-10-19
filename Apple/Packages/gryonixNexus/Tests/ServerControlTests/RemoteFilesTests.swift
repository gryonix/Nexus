import XCTest
@testable import ServerControl

final class RemoteFilesTests: XCTestCase {
    func testKindFromPOSIXPermissions() {
        XCTAssertEqual(RemoteFileEntry.kind(fromPermissions: 0o040755), .directory)
        XCTAssertEqual(RemoteFileEntry.kind(fromPermissions: 0o100644), .file)
        XCTAssertEqual(RemoteFileEntry.kind(fromPermissions: 0o120777), .symlink)
        XCTAssertEqual(RemoteFileEntry.kind(fromPermissions: 0o060660), .other) // block device
        XCTAssertEqual(RemoteFileEntry.kind(fromPermissions: nil), .other)
    }

    func testPathJoinHandlesRoot() {
        XCTAssertEqual(RemotePath.join("/", "opt"), "/opt")
        XCTAssertEqual(RemotePath.join("/opt", "backups"), "/opt/backups")
        XCTAssertEqual(RemotePath.join("/home/admin", "file.txt"), "/home/admin/file.txt")
    }

    func testPathParent() {
        XCTAssertEqual(RemotePath.parent(of: "/opt/backups"), "/opt")
        XCTAssertEqual(RemotePath.parent(of: "/opt"), "/")
        XCTAssertEqual(RemotePath.parent(of: "/"), "/")
    }

    func testPathName() {
        XCTAssertEqual(RemotePath.name(of: "/opt/backups/x.tar.gz"), "x.tar.gz")
        XCTAssertEqual(RemotePath.name(of: "/opt"), "opt")
    }

    func testSortedPutsDirectoriesFirstThenAlphabetical() {
        let entries = [
            RemoteFileEntry(name: "zeta.txt", path: "/zeta.txt", kind: .file),
            RemoteFileEntry(name: "Alpha", path: "/Alpha", kind: .directory),
            RemoteFileEntry(name: "beta.log", path: "/beta.log", kind: .file),
            RemoteFileEntry(name: "backups", path: "/backups", kind: .directory)
        ]
        XCTAssertEqual(RemoteFileEntry.sorted(entries).map(\.name),
                       ["Alpha", "backups", "beta.log", "zeta.txt"])
    }
}
