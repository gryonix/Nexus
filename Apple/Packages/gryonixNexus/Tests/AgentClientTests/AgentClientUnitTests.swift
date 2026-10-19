import XCTest
import SwiftProtobuf
@testable import AgentClient

struct MockTransport: AgentTransport {
    var onUnary: @Sendable (String, Data) async throws -> Data
    var onStream: @Sendable (String, Data) -> AsyncThrowingStream<Data, Error>

    func unary(path: String, request: Data) async throws -> Data {
        try await onUnary(path, request)
    }
    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        onStream(path, request)
    }
}

private func noStream(_: String, _: Data) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { $0.finish() }
}

final class ConnectEnvelopeTests: XCTestCase {
    func testEncodeFlagAndBigEndianLength() {
        let framed = ConnectEnvelope.encode(Data("hello".utf8))
        XCTAssertEqual(framed[0], 0x00)
        XCTAssertEqual([UInt8](framed[1..<5]), [0, 0, 0, 5])
        XCTAssertEqual(framed.suffix(5), Data("hello".utf8))
    }

    func testDecoderRoundtripAndEmpty() {
        var decoder = ConnectEnvelope.Decoder()
        decoder.append(ConnectEnvelope.encode(Data("payload".utf8)))
        XCTAssertEqual(try decoder.next()?.payload, Data("payload".utf8))
        XCTAssertNil(try decoder.next())
    }

    func testDecoderReassemblesAcrossAppends() {
        let framed = ConnectEnvelope.encode(Data("world!!".utf8))
        var decoder = ConnectEnvelope.Decoder()
        decoder.append(framed.prefix(3))
        XCTAssertNil(try decoder.next(), "a partial frame yields nothing yet")
        decoder.append(framed.dropFirst(3))
        XCTAssertEqual(try decoder.next()?.payload, Data("world!!".utf8))
    }

    func testDecoderSplitsTwoFramesInOneAppend() {
        var decoder = ConnectEnvelope.Decoder()
        decoder.append(ConnectEnvelope.encode(Data([1, 2])) + ConnectEnvelope.encode(Data([3])))
        XCTAssertEqual(try decoder.next()?.payload, Data([1, 2]))
        XCTAssertEqual(try decoder.next()?.payload, Data([3]))
        XCTAssertNil(try decoder.next())
    }

    func testEndOfStreamFlagIsDetected() throws {
        var decoder = ConnectEnvelope.Decoder()
        decoder.append(ConnectEnvelope.encode(Data("{}".utf8), flags: ConnectEnvelope.endOfStreamFlag))
        XCTAssertEqual(try decoder.next()?.isEndOfStream, true)
    }

    func testAnImpossiblyLargeFrameIsRefusedInsteadOfWaitedFor() {
        var decoder = ConnectEnvelope.Decoder()
        decoder.append(Data([0, 0x7f, 0xff, 0xff, 0xff]))
        XCTAssertThrowsError(try decoder.next())
    }
}

final class AgentClientUnitTests: XCTestCase {
    func testGetStateEncodesPathAndDecodesResponse() async throws {
        var state = Gryonixnexusd_V1_State()
        state.agentVersion = "1.2.3"
        var service = Gryonixnexusd_V1_Service()
        service.id = "mailcow"
        service.status = .running
        state.services = [service]
        let responseData: Data = try state.serializedBytes()

        let client = AgentClient(transport: MockTransport(
            onUnary: { path, _ in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Control/GetState")
                return responseData
            },
            onStream: noStream))

        let got = try await client.getState()
        XCTAssertEqual(got.agentVersion, "1.2.3")
        XCTAssertEqual(got.services.first?.id, "mailcow")
        XCTAssertEqual(got.services.first?.status, .running)
    }

    func testPairSendsFieldsAndReturnsDevice() async throws {
        var device = Gryonixnexusd_V1_Device()
        device.id = "dev-abc"
        device.scopes = ["read"]
        var response = Gryonixnexusd_V1_PairResponse()
        response.device = device
        let responseData: Data = try response.serializedBytes()

        let client = AgentClient(transport: MockTransport(
            onUnary: { path, request in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Pairing/Pair")
                let sent = try Gryonixnexusd_V1_PairRequest(serializedBytes: request)
                XCTAssertEqual(sent.code, "ABCD-1234")
                XCTAssertEqual(sent.label, "iPhone")
                return responseData
            },
            onStream: noStream))

        let got = try await client.pair(code: "ABCD-1234", devicePublicKey: "ssh-ed25519 AAAA", label: "iPhone")
        XCTAssertEqual(got.id, "dev-abc")
        XCTAssertEqual(got.scopes, ["read"])
    }

    func testRpcErrorPropagates() async {
        let client = AgentClient(transport: MockTransport(
            onUnary: { _, _ in throw AgentError.rpc(code: "permission_denied", message: "invalid or expired pairing code") },
            onStream: noStream))
        do {
            _ = try await client.pair(code: "WRONG", devicePublicKey: "k", label: "l")
            XCTFail("expected an rpc error")
        } catch let AgentError.rpc(code, _) {
            XCTAssertEqual(code, "permission_denied")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testHostMetricsStreamDecodesEachSample() async throws {
        var s1 = Gryonixnexusd_V1_MetricsSample(); s1.cpuPercent = 10
        var s2 = Gryonixnexusd_V1_MetricsSample(); s2.cpuPercent = 20
        let payloads: [Data] = [try s1.serializedBytes(), try s2.serializedBytes()]

        let client = AgentClient(transport: MockTransport(
            onUnary: { _, _ in Data() },
            onStream: { path, _ in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Control/HostMetrics")
                return AsyncThrowingStream { continuation in
                    for payload in payloads { continuation.yield(payload) }
                    continuation.finish()
                }
            }))

        var seen: [Double] = []
        for try await sample in client.hostMetrics(intervalSeconds: 1) {
            seen.append(sample.cpuPercent)
        }
        XCTAssertEqual(seen, [10, 20])
    }
}

/// A byte stream that replays a canned server response
private actor ScriptedStream: AgentByteStream {
    private var remaining: [Data]
    private(set) var closed = false

    init(response: Data) {
        self.remaining = stride(from: 0, to: response.count, by: 7).map {
            response.subdata(in: $0 ..< min($0 + 7, response.count))
        }
    }

    func write(_ data: Data) async throws {}
    func read() async throws -> Data { remaining.isEmpty ? Data() : remaining.removeFirst() }
    func close() async { closed = true }
}

private struct ScriptedFactory: AgentStreamFactory {
    let response: Data
    func open() async throws -> AgentByteStream { ScriptedStream(response: response) }
}

private func chunkedResponse(frames: [Data]) -> Data {
    var body = Data()
    for frame in frames {
        body += Data(String(format: "%x\r\n", frame.count).utf8) + frame + Data("\r\n".utf8)
    }
    body += Data("0\r\n\r\n".utf8)
    let head = "HTTP/1.1 200 OK\r\ncontent-type: application/connect+proto\r\ntransfer-encoding: chunked\r\n\r\n"
    return Data(head.utf8) + body
}

final class ConnectStreamTerminationTests: XCTestCase {
    func testSuccessTrailerEndsTheStreamAndYieldsNoEvent() async throws {
        let response = chunkedResponse(frames: [
            ConnectEnvelope.encode(Data("one".utf8)),
            ConnectEnvelope.encode(Data("two".utf8)),
            ConnectEnvelope.encode(Data("{}".utf8), flags: ConnectEnvelope.endOfStreamFlag),
        ])
        let transport = ConnectTransport(factory: ScriptedFactory(response: response))

        var seen: [String] = []
        for try await payload in transport.serverStream(path: "/x", request: Data()) {
            seen.append(String(decoding: payload, as: UTF8.self))
        }
        XCTAssertEqual(seen, ["one", "two"], "the trailer is an end marker, not an event")
    }

    func testErrorTrailerThrowsAfterDeliveringEarlierEvents() async throws {
        let trailer = #"{"error":{"code":"internal","message":"vpnpanel: docker exited 1"}}"#
        let response = chunkedResponse(frames: [
            ConnectEnvelope.encode(Data("one".utf8)),
            ConnectEnvelope.encode(Data(trailer.utf8), flags: ConnectEnvelope.endOfStreamFlag),
        ])
        let transport = ConnectTransport(factory: ScriptedFactory(response: response))

        var seen: [String] = []
        do {
            for try await payload in transport.serverStream(path: "/x", request: Data()) {
                seen.append(String(decoding: payload, as: UTF8.self))
            }
            XCTFail("expected the trailer to throw")
        } catch let AgentError.rpc(code, message) {
            XCTAssertEqual(code, "internal")
            XCTAssertEqual(message, "vpnpanel: docker exited 1")
        }
        XCTAssertEqual(seen, ["one"], "the event delivered before the failure is not lost")
    }
}
