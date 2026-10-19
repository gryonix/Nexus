import Foundation

/// A failure talking to the agent
public enum AgentError: Error, Sendable, Equatable {
    case rpc(code: String, message: String)
    case transport(String)
    /// A response message could not be decoded against the schema
    case decode(String)
}

extension AgentError: LocalizedError {
    /// The agent's own words, without the enum around them
    public var errorDescription: String? {
        switch self {
        case .rpc(_, let message): return message
        case .transport(let text), .decode(let text): return text
        }
    }
}

public protocol AgentByteStream: Sendable {
    func write(_ data: Data) async throws
    func read() async throws -> Data
    func close() async
}

/// Opens a fresh byte stream per RPC
public protocol AgentStreamFactory: Sendable {
    func open() async throws -> AgentByteStream
}

/// The RPC transport the typed `AgentClient` sits on
public protocol AgentTransport: Sendable {
    func unary(path: String, request: Data) async throws -> Data
    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error>
}
