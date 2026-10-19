import AgentClient
import Foundation
import ServerControl
import ServiceCatalog
import SwiftProtobuf
import XCTest
@testable import AgentControl

/// The VPN-devices seam — the one the devices screen calls
private struct VPNMockTransport: AgentTransport {
    var onUnary: @Sendable (String, Data) async throws -> Data = { _, _ in Data() }

    func unary(path: String, request: Data) async throws -> Data {
        try await onUnary(path, request)
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private func clientList(_ rows: [(id: String, name: String, detail: String)]) throws -> Data {
    var list = Gryonixnexusd_V1_VpnClientList()
    list.clients = rows.map { row in
        var client = Gryonixnexusd_V1_VpnClient()
        client.id = row.id
        client.name = row.name
        client.detail = row.detail
        return client
    }
    return try list.serializedBytes()
}

private func config(text: String, filename: String, qrIsUseful: Bool) throws -> Data {
    var response = Gryonixnexusd_V1_VpnClientConfig()
    response.text = text
    response.filename = filename
    response.qrIsUseful = qrIsUseful
    return try response.serializedBytes()
}

@available(macOS 15.0, *)
final class AgentVPNClientOperationsTests: XCTestCase {
    // MARK: - Listing and mapping

    func testTheProtocolTravelsAsItsCatalogIdAndTheRowsAreMapped() async throws {
        let payload = try clientList([
            (id: "1", name: "phone", detail: "10.9.0.2"),
            (id: "2", name: "laptop", detail: "10.9.0.3"),
        ])
        let sent = Sent()
        let ops = AgentVPNClientOperations(client: AgentClient(transport: VPNMockTransport(
            onUnary: { path, request in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Vpn/ListVpnClients")
                await sent.record(try Gryonixnexusd_V1_ListVpnClientsRequest(serializedBytes: request))
                return payload
            })))

        let devices = try await ops.list(protocol: .amneziaWG)

        let request = await sent.request
        XCTAssertEqual(request?.protocol, ServiceID.amneziaWG.rawValue)
        XCTAssertEqual(devices.map(\.name), ["phone", "laptop"])
        XCTAssertEqual(devices.map(\.detail), ["10.9.0.2", "10.9.0.3"])
    }

    func testAddingAnswersWithTheListingTheServerReturned() async throws {
        let payload = try clientList([(id: "1", name: "my_laptop", detail: "certificate")])
        let ops = AgentVPNClientOperations(client: AgentClient(transport: VPNMockTransport(
            onUnary: { path, _ in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Vpn/AddVpnClient")
                return payload
            })))

        let devices = try await ops.add(protocol: .openVPN, named: "my laptop")
        XCTAssertEqual(devices.map(\.name), ["my_laptop"], "the panel's own name must win, not the request's")
    }

    func testTheServerDecidesWhetherAQRCodeIsWorthDrawing() async throws {
        let payload = try config(text: "client\ndev tun\n", filename: "laptop.ovpn", qrIsUseful: false)
        let ops = AgentVPNClientOperations(client: AgentClient(transport: VPNMockTransport(
            onUnary: { path, _ in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Vpn/GetVpnClientConfig")
                return payload
            })))

        let configuration = try await ops.configuration(protocol: .openVPN, clientID: "1")
        XCTAssertFalse(configuration.qrIsUseful)
        XCTAssertEqual(configuration.fileName, "laptop.ovpn")
        XCTAssertTrue(configuration.text.hasPrefix("client"))
    }

    // MARK: - The gate

    func testConcurrentCallsAreSerializedByAProvidedGate() async throws {
        let gate = AgentChannelGate(limit: 1)
        let peak = Peak()
        let payload = try clientList([])
        let ops = AgentVPNClientOperations(
            client: AgentClient(transport: VPNMockTransport(onUnary: { _, _ in
                await peak.enter()
                try? await Task.sleep(nanoseconds: 2_000_000)
                await peak.leave()
                return payload
            })),
            gate: gate)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask { _ = try? await ops.list(protocol: .wireguardVPN) }
            }
        }
        let highest = await peak.highest
        XCTAssertEqual(highest, 1, "more than one call ran at once under a limit-1 gate")
    }

    func testWithNoGateCallsGenuinelyOverlap() async throws {
        let peak = Peak()
        let payload = try clientList([])
        let ops = AgentVPNClientOperations(
            client: AgentClient(transport: VPNMockTransport(onUnary: { _, _ in
                await peak.enter()
                try? await Task.sleep(nanoseconds: 2_000_000)
                await peak.leave()
                return payload
            })))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask { _ = try? await ops.list(protocol: .wireguardVPN) }
            }
        }
        let highest = await peak.highest
        XCTAssertGreaterThan(highest, 1, "calls did not overlap even without a gate — harness is not sensitive")
    }

    func testFetchingAConfigurationGoesThroughTheGateToo() async throws {
        let gate = AgentChannelGate(limit: 1)
        let peak = Peak()
        let payload = try config(text: "[Interface]", filename: "phone.conf", qrIsUseful: true)
        let ops = AgentVPNClientOperations(
            client: AgentClient(transport: VPNMockTransport(onUnary: { _, _ in
                await peak.enter()
                try? await Task.sleep(nanoseconds: 2_000_000)
                await peak.leave()
                return payload
            })),
            gate: gate)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask { _ = try? await ops.configuration(protocol: .wireguardVPN, clientID: "1") }
            }
        }
        let highest = await peak.highest
        XCTAssertEqual(highest, 1, "fetching a configuration bypassed the gate")
    }

    // MARK: - Refusals

    func testTheServersOwnWordsSurviveAsTheErrorMessage() async throws {
        let ops = AgentVPNClientOperations(client: AgentClient(transport: VPNMockTransport(
            onUnary: { _, _ in
                throw AgentError.rpc(code: "failed_precondition",
                                     message: "this server does not run shadowsocks")
            })))
        do {
            _ = try await ops.list(protocol: .shadowsocks)
            XCTFail("the failure should have been rethrown")
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(text.contains("does not run shadowsocks"), text)
        }
    }

    // MARK: - What can have devices at all

    func testOnlyTheFiveProtocolsCanHaveDevices() {
        XCTAssertEqual(Set(VPNClientProtocols.all), ServiceID.vpnProtocols)
        XCTAssertFalse(VPNClientProtocols.all.contains(.vpnPanel))
    }

    // MARK: - Helpers

    private actor Peak {
        private(set) var current = 0
        private(set) var highest = 0
        func enter() { current += 1; highest = max(highest, current) }
        func leave() { current -= 1 }
    }

    private actor Sent {
        private(set) var request: Gryonixnexusd_V1_ListVpnClientsRequest?
        func record(_ request: Gryonixnexusd_V1_ListVpnClientsRequest) { self.request = request }
    }
}
