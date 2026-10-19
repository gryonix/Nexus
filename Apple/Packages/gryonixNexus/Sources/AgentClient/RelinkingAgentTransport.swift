import Foundation

/// Retries a call once over a fresh link
public struct RelinkingAgentTransport: AgentTransport {
    private let link: @Sendable () async throws -> any AgentTransport
    private let isDeadLink: @Sendable (Error) -> Bool
    private let dropLink: @Sendable () async -> Void

    /// - Parameters: - link: the transport over the current link
    public init(link: @escaping @Sendable () async throws -> any AgentTransport,
                isDeadLink: @escaping @Sendable (Error) -> Bool,
                dropLink: @escaping @Sendable () async -> Void) {
        self.link = link
        self.isDeadLink = isDeadLink
        self.dropLink = dropLink
    }

    public func unary(path: String, request: Data) async throws -> Data {
        do {
            return try await link().unary(path: path, request: request)
        } catch let error where isDeadLink(error) {
            await dropLink()
            return try await link().unary(path: path, request: request)
        }
    }

    public func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var outcome = await relay(path: path, request: request, into: continuation)
                if let error = outcome.error, !outcome.yielded, isDeadLink(error) {
                    await dropLink()
                    outcome = await relay(path: path, request: request, into: continuation)
                }
                continuation.finish(throwing: outcome.error)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Forwards one stream's frames; reports whether any went through
    private func relay(path: String, request: Data,
                       into continuation: AsyncThrowingStream<Data, Error>.Continuation) async
        -> (yielded: Bool, error: Error?) {
        var yielded = false
        do {
            for try await frame in try await link().serverStream(path: path, request: request) {
                yielded = true
                continuation.yield(frame)
            }
            return (yielded, nil)
        } catch {
            return (yielded, error)
        }
    }
}
