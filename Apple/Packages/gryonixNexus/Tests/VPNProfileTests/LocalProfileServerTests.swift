import XCTest
@testable import VPNProfile

final class LocalProfileServerTests: XCTestCase {
    private let profile = Data("<?xml version=\"1.0\"?><plist>…</plist>".utf8)

    func testServesTheProfileOnceWithTheProfileContentType() async throws {
        let server = LocalProfileServer(profile: profile, fileName: "tunnel.mobileconfig")
        let port = try await server.start()
        XCTAssertGreaterThan(port, 0)

        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)\(server.path)"))
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)

        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(data, profile, "a truncated profile is one the system rejects silently")
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Type"),
                       LocalProfileServer.contentType)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Length"), "\(profile.count)")

        await server.waitUntilServed()
    }

    /// It answers one request and closes
    func testStopsAfterTheFirstRequest() async throws {
        let server = LocalProfileServer(profile: profile, fileName: "tunnel.mobileconfig")
        let port = try await server.start()
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)\(server.path)"))

        _ = try await URLSession.shared.data(from: url)
        await server.waitUntilServed()

        do {
            _ = try await URLSession.shared.data(from: url)
            XCTFail("the listener must be gone after serving")
        } catch {
            // Connection refused — which is the point.
        }
    }

    func testClosesItselfWhenNobodyComes() async throws {
        let server = LocalProfileServer(profile: profile,
                                        fileName: "tunnel.mobileconfig",
                                        patience: .milliseconds(200))
        let port = try await server.start()
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)\(server.path)"))

        try await Task.sleep(for: .milliseconds(700))
        do {
            _ = try await URLSession.shared.data(from: url)
            XCTFail("the listener must close when its deadline passes")
        } catch {
            // Connection refused — which is the point.
        }
    }

    func testAnyOtherAddressGetsNothingAndDoesNotUseUpTheProfile() async throws {
        let server = LocalProfileServer(profile: profile, fileName: "tunnel.mobileconfig")
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let guess = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/tunnel.mobileconfig"))
        let (_, refused) = try await URLSession.shared.data(from: guess)
        XCTAssertEqual((refused as? HTTPURLResponse)?.statusCode, 404)

        let real = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)\(server.path)"))
        let (data, _) = try await URLSession.shared.data(from: real)
        XCTAssertEqual(data, profile, "a stranger's request must not spend the one answer")
    }

    func testAFileNameCannotBreakTheResponse() {
        XCTAssertEqual(LocalProfileServer.safe("Danila's \"phone\"\r\nX: y/z.mobileconfig"),
                       "Danila's -phone---X- y-z.mobileconfig")
        XCTAssertEqual(LocalProfileServer.safe(""), "profile.mobileconfig")
    }

    func testIsNotReachableFromOffTheLoopbackInterface() async throws {
        let server = LocalProfileServer(profile: profile, fileName: "tunnel.mobileconfig")
        let port = try await server.start()
        defer { Task { await server.stop() } }

        guard let address = Self.firstNonLoopbackIPv4() else {
            throw XCTSkip("no non-loopback IPv4 address on this machine")
        }
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://\(address):\(port)/x")))
        request.timeoutInterval = 2
        do {
            _ = try await URLSession.shared.data(for: request)
            XCTFail("the listener answered on \(address) — it must be loopback-only")
        } catch {
        }
    }

    private static func firstNonLoopbackIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(pointer.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let sa = pointer.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return String(cString: host)
        }
        return nil
    }
}
