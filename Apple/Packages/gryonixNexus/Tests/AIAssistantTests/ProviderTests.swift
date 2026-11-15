import XCTest
@testable import AIAssistant

final class ProviderTests: XCTestCase {
    private func json(_ request: AIHTTPRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]) ?? [:]
    }

    func testOpenAIRequest() {
        let config = AIProviderConfig(providerID: "openai", model: "gpt-x")
        let request = AIRequestBuilder.build(config: config, apiKey: "k1", system: "sys",
                                             messages: [AIMessage(role: .user, content: "hi")])
        XCTAssertEqual(request.url, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.headers["Authorization"], "Bearer k1")
        let body = json(request)
        XCTAssertEqual(body["stream"] as? Bool, true)
        let messages = body["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.first?["role"], "system")
        XCTAssertEqual(messages?.last?["content"], "hi")
    }

    func testAnthropicRequest() {
        let config = AIProviderConfig(providerID: "anthropic", model: "m")
        let request = AIRequestBuilder.build(config: config, apiKey: "k2", system: "sys",
                                             messages: [AIMessage(role: .user, content: "hi")])
        XCTAssertEqual(request.url, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.headers["x-api-key"], "k2")
        XCTAssertNil(request.headers["Authorization"])
        let body = json(request)
        XCTAssertEqual(body["system"] as? String, "sys")
        XCTAssertEqual((body["messages"] as? [Any])?.count, 1)
        XCTAssertNotNil(body["max_tokens"])
    }

    func testOpenAIImageBecomesDataURLPart() {
        let config = AIProviderConfig(providerID: "openai", model: "gpt-x")
        let image = AIImage(mediaType: "image/jpeg", base64: "QUJD")
        let request = AIRequestBuilder.build(config: config, apiKey: "k", system: "s",
                                             messages: [AIMessage(role: .user, content: "what is this", images: [image])])
        let parts = (json(request)["messages"] as? [[String: Any]])?.last?["content"] as? [[String: Any]]
        XCTAssertEqual(parts?.first?["text"] as? String, "what is this")
        let url = (parts?.last?["image_url"] as? [String: String])?["url"]
        XCTAssertEqual(url, "data:image/jpeg;base64,QUJD")
    }

    func testAnthropicImageBecomesBase64Block() {
        let config = AIProviderConfig(providerID: "anthropic", model: "m")
        let image = AIImage(mediaType: "image/png", base64: "QUJD")
        let request = AIRequestBuilder.build(config: config, apiKey: "k", system: "s",
                                             messages: [AIMessage(role: .user, content: "look", images: [image])])
        let parts = (json(request)["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]
        let source = parts?.first?["source"] as? [String: String]
        XCTAssertEqual(source?["media_type"], "image/png")
        XCTAssertEqual(source?["data"], "QUJD")
        XCTAssertEqual(parts?.last?["text"] as? String, "look")
    }

    func testOllamaNeedsNoKeyAndTrimsSlash() {
        let config = AIProviderConfig(providerID: "ollama", model: "llama3.2:3b",
                                      baseURL: "http://127.0.0.1:21434/v1/")
        let request = AIRequestBuilder.build(config: config, apiKey: nil, system: "s", messages: [])
        XCTAssertEqual(request.url, "http://127.0.0.1:21434/v1/chat/completions")
        XCTAssertNil(request.headers["Authorization"])
        XCTAssertTrue(config.isLocal)
    }

    func testOpenAIStream() {
        var parser = AIStreamParser(format: .openAI)
        XCTAssertEqual(parser.feed(line: "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}"), [.text("Hel")])
        XCTAssertEqual(parser.feed(line: "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":7}}"),
                       [.usage(input: 5, output: 7)])
        XCTAssertEqual(parser.feed(line: "data: [DONE]"), [.done])
        XCTAssertEqual(parser.feed(line: ": keepalive"), [])
    }

    func testAnthropicStream() {
        var parser = AIStreamParser(format: .anthropic)
        XCTAssertEqual(parser.feed(line: "data: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":11}}}"), [])
        XCTAssertEqual(parser.feed(line: "data: {\"type\":\"content_block_delta\",\"delta\":{\"text\":\"Yo\"}}"), [.text("Yo")])
        XCTAssertEqual(parser.feed(line: "data: {\"type\":\"message_delta\",\"usage\":{\"output_tokens\":3}}"),
                       [.usage(input: 11, output: 3)])
        XCTAssertEqual(parser.feed(line: "data: {\"type\":\"message_stop\"}"), [.done])
    }

    func testStreamError() {
        var parser = AIStreamParser(format: .openAI)
        XCTAssertEqual(parser.feed(line: "data: {\"error\":{\"message\":\"bad key\"}}"), [.failure("bad key")])
    }
}
