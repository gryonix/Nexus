import AIAssistant
import Foundation

struct AIChatFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Sends one streaming request and yields its events.
enum AIChatClient {
    static func stream(_ request: AIHTTPRequest, format: AIWireFormat) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request, format: format, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(_ request: AIHTTPRequest, format: AIWireFormat,
                            continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation) async throws {
        guard let url = URL(string: request.url) else { throw AIChatFailure(message: "Bad address") }
        var urlRequest = URLRequest(url: url, timeoutInterval: 120)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIChatFailure(message: await errorText(bytes, status: http.statusCode))
        }
        var parser = AIStreamParser(format: format)
        for try await line in bytes.lines {
            for event in parser.feed(line: line) {
                if case .failure(let text) = event { throw AIChatFailure(message: text) }
                continuation.yield(event)
            }
        }
    }

    private static func errorText(_ bytes: URLSession.AsyncBytes, status: Int) async -> String {
        var text = ""
        do {
            for try await line in bytes.lines {
                text += line
                if text.count > 400 { break }
            }
        } catch {}
        return "HTTP \(status) \(text.prefix(300))"
    }
}
