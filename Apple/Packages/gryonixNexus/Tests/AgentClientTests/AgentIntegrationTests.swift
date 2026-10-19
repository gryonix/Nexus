#if canImport(Darwin)
import XCTest
import Darwin
import SwiftProtobuf
@testable import AgentClient

final class AgentIntegrationTests: XCTestCase {
    private var server: Process?
    private let socketPath = "/tmp/gd-it-\(getpid()).sock"
    private let stateDir = "/tmp/gd-it-\(getpid())-state"

    private var binaryPath: String {
        // .../Apple/Packages/gryonixNexus/Tests/AgentClientTests/<thisfile> → repo root.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("Server/gryonixnexusd/target/debug/gryonixnexusd").path
    }

    override func tearDown() {
        server?.terminate()
        server = nil
        try? FileManager.default.removeItem(atPath: socketPath)
        try? FileManager.default.removeItem(atPath: stateDir)
    }

    func testEndToEndAgainstRealAgent() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: binaryPath),
                          "gryonixnexusd debug binary not built (cargo build in Agent/gryonixnexusd)")
        try? FileManager.default.removeItem(atPath: socketPath)
        try? FileManager.default.removeItem(atPath: stateDir)

        let code = try mintPairingCode()

        // 2) Start the server and wait for the socket.
        let server = try launch(arguments: [])
        self.server = server
        try await waitForSocket()

        let client = AgentClient(factory: UnixSocketStreamFactory(path: socketPath))

        let state = try await client.getState()
        XCTAssertFalse(state.agentVersion.isEmpty)
        XCTAssertFalse(state.host.arch.isEmpty)

        let device = try await client.pair(
            code: code, devicePublicKey: "ssh-ed25519 AAAAINTEGRATION", label: "iPhone")
        XCTAssertFalse(device.id.isEmpty)
        XCTAssertEqual(device.scopes, ["read"])
        let devices = try await client.listDevices()
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.id, device.id)

        // 5) The code is single-use: pairing again is rejected.
        do {
            _ = try await client.pair(code: code, devicePublicKey: "ssh-ed25519 AAAAINTEGRATION", label: "iPhone")
            XCTFail("reused pairing code should be rejected")
        } catch let AgentError.rpc(errorCode, _) {
            XCTAssertEqual(errorCode, "permission_denied")
        }

        // 6) HostMetrics streaming — collect two samples over the envelope wire.
        var samples: [Gryonixnexusd_V1_MetricsSample] = []
        for try await sample in client.hostMetrics(intervalSeconds: 1) {
            samples.append(sample)
            if samples.count == 2 { break }
        }
        XCTAssertEqual(samples.count, 2)
        XCTAssertGreaterThan(samples[1].sampledAt, 0)
    }

    /// Management (Phase 2) against the real agent
    func testManagementRejectsUnknownServicesAndActions() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: binaryPath),
                          "gryonixnexusd debug binary not built (cargo build in Agent/gryonixnexusd)")
        try? FileManager.default.removeItem(atPath: socketPath)
        try? FileManager.default.removeItem(atPath: stateDir)

        let server = try launch(arguments: [])
        self.server = server
        try await waitForSocket()

        let client = AgentClient(factory: UnixSocketStreamFactory(path: socketPath))

        // Unary path: an id outside the catalog.
        do {
            _ = try await client.serviceStatus(serviceID: "definitely-not-a-service")
            XCTFail("an unknown service id must be refused")
        } catch let AgentError.rpc(code, message) {
            XCTAssertEqual(code, "invalid_argument")
            XCTAssertTrue(message.contains("definitely-not-a-service"), message)
        }

        // Streaming path: the same gate, plus the enveloped request framing.
        await assertControlRejected(client, serviceID: "nope; rm -rf /", action: .restart)
        await assertControlRejected(client, serviceID: "vaultwarden", action: .unspecified)
    }

    private func assertControlRejected(_ client: AgentClient, serviceID: String,
                                       action: Gryonixnexusd_V1_ServiceAction,
                                       file: StaticString = #filePath, line: UInt = #line) async {
        do {
            for try await _ in client.controlService(serviceID: serviceID, action: action) {}
            XCTFail("ControlService(\(serviceID), \(action)) must be refused", file: file, line: line)
        } catch let AgentError.rpc(code, _) {
            XCTAssertEqual(code, "invalid_argument", file: file, line: line)
        } catch {
            XCTFail("unexpected error: \(error)", file: file, line: line)
        }
    }

    // MARK: - Harness

    private func mintPairingCode() throws -> String {
        let process = try launch(arguments: ["pair-code"])
        let pipe = process.standardOutput as! Pipe
        process.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard let range = out.range(of: "[0-9A-Z]{4}-[0-9A-Z]{4}", options: .regularExpression) else {
            throw XCTSkip("could not parse a pairing code from: \(out)")
        }
        return String(out[range])
    }

    private func launch(arguments: [String]) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        process.environment = ["GRYONIXNEXUSD_SOCKET": socketPath, "GRYONIXNEXUSD_STATE_DIR": stateDir]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        return process
    }

    private func waitForSocket() async throws {
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: socketPath) { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw AgentError.transport("agent socket never appeared at \(socketPath)")
    }
}

/// A Unix-socket byte stream for the integration test
final class UnixSocketStreamFactory: AgentStreamFactory, @unchecked Sendable {
    private let path: String
    init(path: String) { self.path = path }

    func open() async throws -> AgentByteStream {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentError.transport("socket() failed") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let sunPathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { rawPtr in
            path.withCString { cstr in
                rawPtr.withMemoryRebound(to: CChar.self, capacity: sunPathCapacity) { dst in
                    strncpy(dst, cstr, sunPathCapacity - 1)
                }
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard rc == 0 else {
            close(fd)
            throw AgentError.transport("connect() failed: \(errno)")
        }
        return UnixSocketByteStream(fd: fd)
    }
}

final class UnixSocketByteStream: AgentByteStream, @unchecked Sendable {
    private let fd: Int32
    private let queue = DispatchQueue(label: "agentclient.unixsocket")
    init(fd: Int32) { self.fd = fd }

    func write(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                var remaining = data
                while !remaining.isEmpty {
                    let written = remaining.withUnsafeBytes { Darwin.write(self.fd, $0.baseAddress, remaining.count) }
                    if written <= 0 {
                        cont.resume(throwing: AgentError.transport("write() failed"))
                        return
                    }
                    remaining = remaining.dropFirst(written)
                }
                cont.resume()
            }
        }
    }

    func read() async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            queue.async {
                var buffer = [UInt8](repeating: 0, count: 65536)
                let n = Darwin.read(self.fd, &buffer, buffer.count)
                if n < 0 { cont.resume(throwing: AgentError.transport("read() failed")) }
                else if n == 0 { cont.resume(returning: Data()) }
                else { cont.resume(returning: Data(buffer[0..<n])) }
            }
        }
    }

    func close() async {
        queue.sync { _ = Darwin.close(fd) }
    }
}
#endif
