import XCTest
@testable import AIAssistant

final class StateTests: XCTestCase {
    func testLedgerPerMonth() {
        var ledger = AITokenLedger()
        let nov = Date(timeIntervalSince1970: 1_793_000_000)
        let dec = nov.addingTimeInterval(40 * 86_400)
        ledger.add(tokens: 100, at: nov)
        ledger.add(tokens: 50, at: nov)
        ledger.add(tokens: -5, at: nov)
        ledger.add(tokens: 7, at: dec)
        XCTAssertEqual(ledger.used(at: nov), 150)
        XCTAssertEqual(ledger.used(at: dec), 7)
    }

    func testBudgetStates() {
        XCTAssertEqual(AITokenLedger.state(used: 999, limit: 0), .unlimited)
        XCTAssertEqual(AITokenLedger.state(used: 79, limit: 100), .ok)
        XCTAssertEqual(AITokenLedger.state(used: 80, limit: 100), .nearLimit)
        XCTAssertEqual(AITokenLedger.state(used: 100, limit: 100), .reached)
    }

    func testHistoryGroupsAndRoundTrip() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        var history = AIChatHistory()
        for (title, days) in [("a", 0.0), ("b", 1.0), ("c", 3.0), ("d", 30.0)] {
            history.upsert(AIChat(title: title, at: now.addingTimeInterval(-days * 86_400)))
        }
        let groups = history.groups(now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.0), [.today, .yesterday, .lastWeek, .earlier])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        let store = AIChatFileStore(url: url)
        store.save(history)
        XCTAssertEqual(store.load(), history)
        try? FileManager.default.removeItem(at: url)
    }

    func testUpsertReplacesAndDelete() {
        var history = AIChatHistory()
        var chat = AIChat(title: "x")
        history.upsert(chat)
        chat.title = "y"
        history.upsert(chat)
        XCTAssertEqual(history.chats.count, 1)
        XCTAssertEqual(history.chats[0].title, "y")
        history.delete(id: chat.id)
        XCTAssertTrue(history.chats.isEmpty)
    }

    func testMissingFileLoadsEmpty() {
        let store = AIChatFileStore(url: URL(fileURLWithPath: "/nonexistent/none.json"))
        XCTAssertTrue(store.load().chats.isEmpty)
    }

    func testPromptRedactsAndNeverClaimsAction() {
        let context = AIContext(kind: .service, title: "web",
                                sections: [("Logs", "ok\nPASSWORD=abc123\nend")])
        let text = AIPrompts.contextMessage(context)
        XCTAssertFalse(text.contains("abc123"))
        XCTAssertTrue(text.contains("### Logs"))
        let system = AIPrompts.systemPrompt(languageName: "German")
        XCTAssertTrue(system.contains("cannot run commands"))
        XCTAssertTrue(system.contains("German"))
    }

    func testPromptKeepsTail() {
        let long = String(repeating: "x ", count: 5000) + "LASTLINE"
        let text = AIPrompts.contextMessage(AIContext(kind: .operation, title: "t", sections: [("Log", long)]))
        XCTAssertTrue(text.contains("LASTLINE"))
        XCTAssertLessThan(text.count, 7000)
    }

    func testMarkdown() {
        let blocks = MarkdownBlocks.parse("# T\nhello\n\n- a\n- b\n\n```sh\nls -l\n```\n1. x\n2. y")
        XCTAssertEqual(blocks, [.heading(1, "T"), .paragraph("hello"), .bullets(["a", "b"]),
                                .code(language: "sh", text: "ls -l"), .numbered(["x", "y"])])
    }

    func testMarkdownOpenFence() {
        XCTAssertEqual(MarkdownBlocks.parse("```\nls"), [.code(language: "", text: "ls")])
    }

    func testRAMTable() {
        XCTAssertEqual(OllamaRAM.requiredGB(model: "llama3.2:3b"), 4)
        XCTAssertEqual(OllamaRAM.requiredGB(model: "qwen2.5:7b"), 8)
        XCTAssertEqual(OllamaRAM.requiredGB(model: "llama3.1:8b-instruct-q4"), 8)
        XCTAssertEqual(OllamaRAM.requiredGB(model: "qwen2.5:14b"), 16)
        XCTAssertEqual(OllamaRAM.requiredGB(model: "qwen2.5:32b"), 32)
        XCTAssertEqual(OllamaRAM.requiredGB(model: "mixtral:8x7b"), 32)
        XCTAssertNil(OllamaRAM.requiredGB(model: "phi3:mini"))
    }

    func testRAMVerdict() {
        let gb: UInt64 = 1_073_741_824
        XCTAssertEqual(OllamaRAM.verdict(model: "qwen2.5:14b", machineBytes: 8 * gb), .tooLow(needGB: 16, haveGB: 8))
        XCTAssertEqual(OllamaRAM.verdict(model: "qwen2.5:7b", machineBytes: 8 * gb), .enough)
        XCTAssertEqual(OllamaRAM.verdict(model: "qwen2.5:7b", machineBytes: nil), .unknown)
    }

    func testWeeklyDigest() {
        let t = Date(timeIntervalSince1970: 0)
        let text = AIWeeklyDigest.lines(server: "orion", samples: [
            AIUsageSample(time: t, cpuPercent: 10, memoryFraction: 0.5, diskFraction: 0.6, temperature: nil),
            AIUsageSample(time: t.addingTimeInterval(1), cpuPercent: 30, memoryFraction: 0.7, diskFraction: 0.7, temperature: 60)
        ])
        XCTAssertTrue(text.contains("CPU avg 20% max 30%"))
        XCTAssertTrue(text.contains("disk 60% -> 70%"))
        XCTAssertTrue(AIWeeklyDigest.lines(server: "x", samples: []).contains("no history"))
    }
}
