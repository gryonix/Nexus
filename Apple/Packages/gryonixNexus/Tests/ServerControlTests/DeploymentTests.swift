import XCTest
import ServiceCatalog
@testable import ServerControl

final class DeploymentTests: XCTestCase {
    private func makeDeployment() -> Deployment {
        Deployment(
            name: "Home mail",
            topology: .vpsRelayWithHomeBackend,
            domain: "example.com",
            entry: HostEndpoint(host: "203.0.113.4", user: "admin"),
            homeWGAddress: "10.8.0.2",
            services: [.mailcow, .vaultwarden]
        )
    }

    /// The runtime rebuilds the admin-lockdown host matcher from this context
    func testServiceContextCarriesAdditionalDomains() {
        var deployment = makeDeployment()
        deployment.additionalDomains = ["example.net", "example.org"]
        let context = deployment.serviceContext
        XCTAssertEqual(context.additionalDomains, ["example.net", "example.org"])
        XCTAssertEqual(context.mirroredHostnames(of: "cloud.example.com"),
                       ["cloud.example.net", "cloud.example.org"])
    }

    func testAdditionalDomainsSurviveEncoding() throws {
        var deployment = makeDeployment()
        deployment.additionalDomains = ["example.net"]
        let data = try DeploymentListCodec.encode([deployment])
        XCTAssertEqual(try DeploymentListCodec.decode(data), [deployment])

        // Records written before the field existed must still load.
        var list = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        list[0].removeValue(forKey: "additionalDomains")
        let stripped = try JSONSerialization.data(withJSONObject: list)
        XCTAssertEqual(try DeploymentListCodec.decode(stripped).first?.additionalDomains, [])
    }

    func testCodableRoundTrip() throws {
        var deployment = makeDeployment()
        deployment.metricsIndicatorStyle = .rings
        let data = try DeploymentListCodec.encode([deployment])
        let decoded = try DeploymentListCodec.decode(data)
        XCTAssertEqual(decoded, [deployment])
        XCTAssertEqual(decoded.first?.metricsIndicatorStyle, .rings)
    }

    func testDecodingPre11StorageDefaultsNewFields() throws {
        var deployment = makeDeployment()
        deployment.metricsIndicatorStyle = .rings
        deployment.usesPasswordAuth = true
        deployment.iconSymbol = "house.fill"
        deployment.tintName = "green"
        deployment.scope = .localOnly
        let data = try DeploymentListCodec.encode([deployment])
        var list = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        list[0].removeValue(forKey: "metricsIndicatorStyle")
        list[0].removeValue(forKey: "usesPasswordAuth")
        list[0].removeValue(forKey: "iconSymbol")
        list[0].removeValue(forKey: "tintName")
        list[0].removeValue(forKey: "scope")
        let stripped = try JSONSerialization.data(withJSONObject: list)
        let decoded = try DeploymentListCodec.decode(stripped)
        XCTAssertNil(decoded.first?.metricsIndicatorStyle)
        XCTAssertEqual(decoded.first?.usesPasswordAuth, false,
                       "records without the field default to key auth")
        XCTAssertNil(decoded.first?.iconSymbol)
        XCTAssertNil(decoded.first?.tintName)
        XCTAssertEqual(decoded.first?.scope, .publicInternet,
                       "records without the field default to a public-internet deployment")
    }

    func testServiceContextMirrorsDeployment() {
        let context = makeDeployment().serviceContext
        XCTAssertEqual(context.domain, "example.com")
        XCTAssertEqual(context.sshUser, "admin")
        XCTAssertEqual(context.settings.vaultwardenContainer, "vaultwarden")
    }

    func testServicesHostFollowsTopology() {
        var deployment = makeDeployment()
        XCTAssertEqual(deployment.servicesHost, .home)

        deployment = Deployment(name: "Single server", topology: .singleHost,
                                entry: HostEndpoint(host: "203.0.113.9", user: "ops"))
        XCTAssertEqual(deployment.servicesHost, .vps)
        XCTAssertFalse(deployment.hasHomeHost)
    }

    func testDashboardConfigBridge() {
        let config = makeDeployment().dashboardConfig
        XCTAssertEqual(config.vpsHost, "203.0.113.4")
        XCTAssertEqual(config.sshUser, "admin")
        XCTAssertEqual(config.homeWGAddress, "10.8.0.2")
        XCTAssertEqual(config.mailcowRestartTimeoutSeconds, 120)
        XCTAssertTrue(config.isConnectable)
    }

    func testInstalledServicesStableOrder() {
        let services = makeDeployment().installedServices.map(\.id)
        XCTAssertEqual(services, [.mailcow, .vaultwarden])
    }

    func testTimeoutClassMapping() {
        let timeouts = OperationTimeouts()
        XCTAssertEqual(timeouts.duration(for: .quick), .seconds(15))
        XCTAssertEqual(timeouts.duration(for: .restart), .seconds(120))
        XCTAssertEqual(timeouts.duration(for: .long), .seconds(600))
    }
}
