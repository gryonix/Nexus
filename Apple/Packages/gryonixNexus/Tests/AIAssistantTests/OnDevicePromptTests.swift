import XCTest
@testable import AIAssistant

final class OnDevicePromptTests: XCTestCase {
    func testOneQuestionIsSentAsIs() {
        XCTAssertEqual(AIOnDevicePrompt.build([AIMessage(role: .user, content: "Explain ls -la")]), "Explain ls -la")
    }

    func testEarlierTurnsComeFirstAndTheOldestAreCut() {
        let messages = [
            AIMessage(role: .user, content: String(repeating: "a", count: 50)),
            AIMessage(role: .assistant, content: "short answer"),
            AIMessage(role: .user, content: "and now?")
        ]
        let prompt = AIOnDevicePrompt.build(messages, budget: 40)
        XCTAssertEqual(prompt, "Conversation so far:\nAssistant: short answer\n\nNow:\nand now?")
    }

    func testALongLogKeepsItsEnd() {
        let log = String(repeating: "x", count: 100) + "ERROR at the end"
        XCTAssertTrue(AIOnDevicePrompt.build([AIMessage(role: .user, content: log)], budget: 30).hasSuffix("ERROR at the end"))
        XCTAssertEqual(AIProviderConfig.suggestedModel(AIProviderConfig.onDeviceID), "on-device")
        XCTAssertTrue(AIProviderConfig(providerID: "apple", model: "on-device").isLocal)
    }
}
