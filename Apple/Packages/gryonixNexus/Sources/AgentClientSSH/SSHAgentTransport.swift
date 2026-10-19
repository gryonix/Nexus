import Foundation
import AgentClient
@preconcurrency import Citadel

@available(macOS 15.0, *)
public struct SSHAgentTransport: AgentTransport {
    private let client: SSHClient
    private let bridgeCommand: String
    /// Which installation of the app is calling — see `HTTPWire.request`
    private let deviceUID: String

    public static let defaultBridgeCommand = "sudo -n /usr/local/bin/gryonixnexusd bridge"

    /// - Parameters: - client: an already-connected Citadel SSH client
    public init(client: SSHClient,
                bridgeCommand: String = SSHAgentTransport.defaultBridgeCommand,
                deviceUID: String = "") {
        self.client = client
        self.bridgeCommand = bridgeCommand
        self.deviceUID = deviceUID
    }

    public func unary(path: String, request: Data) async throws -> Data {
        var response = Data()
        try await client.withExec(bridgeCommand) { inbound, outbound in
            let stream = ExecByteStream(inbound: inbound, outbound: outbound)
            let reader = ByteReader(stream: stream)
            do {
                try await stream.write(HTTPWire.request(path: path, contentType: "application/proto",
                                                        body: request, deviceUID: deviceUID))
                let head = try await HTTPWire.readHead(reader)
                let body = try await HTTPWire.readBody(reader, head)
                guard head.status == 200 else {
                    throw parseConnectError(from: body, status: head.status)
                }
                response = body
            } catch {
                throw Self.explained(error, stream)
            }
        }
        return response
    }

    private static func explained(_ error: Error, _ stream: ExecByteStream) -> Error {
        if case AgentError.rpc = error { return error }
        let said = stream.stderrText
        guard !said.isEmpty else { return error }
        return AgentError.transport("the agent bridge did not start: \(said)")
    }

    public func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await client.withExec(bridgeCommand) { inbound, outbound in
                        let stream = ExecByteStream(inbound: inbound, outbound: outbound)
                        let reader = ByteReader(stream: stream)
                        do {
                            let enveloped = ConnectEnvelope.encode(request)
                            try await stream.write(HTTPWire.request(
                                path: path, contentType: "application/connect+proto", body: enveloped,
                                deviceUID: deviceUID))
                            let head = try await HTTPWire.readHead(reader)
                            guard head.status == 200 else {
                                let body = try await HTTPWire.readBody(reader, head)
                                throw parseConnectError(from: body, status: head.status)
                            }
                            var decoder = ConnectEnvelope.Decoder()
                            var ended = false
                            try await HTTPWire.readChunks(reader, head) { chunk in
                                decoder.append(chunk)
                                while let frame = try decoder.next() {
                                    if frame.isEndOfStream {
                                        if let err = parseConnectTrailer(frame.payload) { throw err }
                                        ended = true
                                        return false
                                    }
                                    continuation.yield(frame.payload)
                                }
                                return true
                            }
                            guard ended else { throw AgentError.transport(ConnectEnvelope.cutOffMessage) }
                        } catch {
                            throw Self.explained(error, stream)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@available(macOS 15.0, *)
extension SSHAgentTransport {
    /// The SSH session stopped answering channel requests
    public static func isDeadLink(_ error: Error) -> Bool {
        (error as? CitadelError) == .channelCreationFailed
    }
}
