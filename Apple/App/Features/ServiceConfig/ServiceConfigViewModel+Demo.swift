import Foundation

extension ServiceConfigViewModel {
    static let demoDomain = "example.net"
    static let demoPublicIP = "203.0.113.10"
    static let demoLocalIP = "192.168.1.50"

    func useDemoAddressesIfLocked() {
        guard !LicenseStore.isUnlocked else { return }
        publicIP = localOnly ? Self.demoLocalIP : Self.demoPublicIP
        domain = localOnly ? Self.demoLocalIP : Self.demoDomain
        homeNetworkAddress = isPairTopology ? Self.demoLocalIP : ""
        additionalDomains = []
        serviceHostnames = [:]
        vpnHostname = ""
        reverseDNSHostname = ""
    }
}
