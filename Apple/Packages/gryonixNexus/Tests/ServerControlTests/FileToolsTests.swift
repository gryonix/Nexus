import XCTest
@testable import ServerControl

final class FileToolsTests: XCTestCase {
    func testBreadcrumbsWalkFromRoot() {
        let crumbs = RemotePath.breadcrumbs(of: "/home/user/docs")
        XCTAssertEqual(crumbs.map(\.name), ["/", "home", "user", "docs"])
        XCTAssertEqual(crumbs.map(\.path), ["/", "/home", "/home/user", "/home/user/docs"])
        XCTAssertEqual(RemotePath.breadcrumbs(of: "/").count, 1)
    }

    func testBatchRenameSkipsClashesAndNoChange() {
        let changes = BatchRename.plan(names: ["a_old.txt", "b.txt", "c_old.txt"],
                                       existing: ["a_old.txt", "b.txt", "c_old.txt", "c_new.txt"],
                                       find: "_old", replace: "_new")
        XCTAssertEqual(changes.map(\.newName), ["a_new.txt"])
    }

    func testBatchRenameRefusesSeparatorsAndEmptyFind() {
        XCTAssertTrue(BatchRename.plan(names: ["a"], existing: ["a"], find: "a", replace: "x/y").isEmpty)
        XCTAssertTrue(BatchRename.plan(names: ["a"], existing: ["a"], find: "", replace: "x").isEmpty)
    }

    func testSearchMatchesSubstringAndWildcard() {
        XCTAssertTrue(FileSearch.matches("Report.PDF", pattern: "report"))
        XCTAssertTrue(FileSearch.matches("report.pdf", pattern: "*.pdf"))
        XCTAssertFalse(FileSearch.matches("report.txt", pattern: "*.pdf"))
        XCTAssertFalse(FileSearch.matches("x", pattern: "  "))
    }

    func testWalkIsRecursiveAndLimited() async throws {
        let tree: [String: [RemoteFileEntry]] = [
            "/": [dir("a", "/"), file("hit1.txt", "/")],
            "/a": [file("hit2.txt", "/a"), dir("b", "/a")],
            "/a/b": [file("hit3.txt", "/a/b")],
        ]
        let all = try await FileSearch.walk("/", matching: "hit", limit: 10) { tree[$0] ?? [] }
        XCTAssertEqual(all.map(\.name).sorted(), ["hit1.txt", "hit2.txt", "hit3.txt"])
        let two = try await FileSearch.walk("/", matching: "hit", limit: 2) { tree[$0] ?? [] }
        XCTAssertEqual(two.count, 2)
    }

    func testWalkStopsWhenCancelled() async {
        let task = Task { () -> Bool in
            do {
                _ = try await FileSearch.walk("/", matching: "x", limit: 5) { _ in [] }
                return false
            } catch { return error is CancellationError }
        }
        task.cancel()
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
    }

    func testPreviewKindsAndThumbnailLimit() {
        XCTAssertEqual(file("a.PNG", "/", size: 10).previewKind, .image)
        XCTAssertEqual(file("notes.md", "/").previewKind, .text)
        XCTAssertEqual(file("blob.bin", "/").previewKind, .none)
        XCTAssertTrue(file("a.jpg", "/", size: 2 * 1024 * 1024).canThumbnail)
        XCTAssertFalse(file("a.jpg", "/", size: 2 * 1024 * 1024 + 1).canThumbnail)
    }

    func testShortcutsKeepTwentyRecentsAndToggleBookmarks() {
        var shortcuts = FileShortcuts()
        for index in 0..<25 { shortcuts.noteOpened("/f\(index)") }
        XCTAssertEqual(shortcuts.recents.count, 20)
        XCTAssertEqual(shortcuts.recents.first, "/f24")
        shortcuts.noteOpened("/f10")
        XCTAssertEqual(shortcuts.recents.first, "/f10")
        XCTAssertEqual(shortcuts.recents.filter { $0 == "/f10" }.count, 1)
        shortcuts.toggleBookmark("/x")
        XCTAssertTrue(shortcuts.isBookmarked("/x"))
        shortcuts.renamed("/x", to: "/y")
        XCTAssertTrue(shortcuts.isBookmarked("/y"))
        shortcuts.toggleBookmark("/y")
        XCTAssertTrue(shortcuts.bookmarks.isEmpty)
    }

    private func dir(_ name: String, _ parent: String) -> RemoteFileEntry {
        RemoteFileEntry(name: name, path: RemotePath.join(parent, name), kind: .directory)
    }

    private func file(_ name: String, _ parent: String, size: UInt64? = nil) -> RemoteFileEntry {
        RemoteFileEntry(name: name, path: RemotePath.join(parent, name), kind: .file, size: size)
    }
}
