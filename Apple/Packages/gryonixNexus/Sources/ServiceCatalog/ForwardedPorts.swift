/// The ports a relay carries in from the internet
public enum ForwardedPorts {
    /// DNS serves the home network, never the internet
    static let homeOnlyPorts: Set<Int> = [53]
    public static func tcp(services: [any ManagedService], context: ServiceContext) -> [Int] {
        var ports: Set<Int> = [80]
        if services.contains(where: { $0.webIngress(context) != nil }) {
            ports.insert(443)
        }
        for service in services where !service.requiresHomeMachine {
            for port in service.firewallPorts(context) where port.proto == .tcp && !homeOnlyPorts.contains(port.port) {
                ports.insert(port.port)
            }
        }
        return ports.sorted()
    }

    public static func udp(services: [any ManagedService], context: ServiceContext) -> [Int] {
        var ports: Set<Int> = []
        for service in services where !service.requiresHomeMachine {
            for port in service.firewallPorts(context) where port.proto == .udp && !homeOnlyPorts.contains(port.port) {
                ports.insert(port.port)
            }
        }
        return ports.sorted()
    }
}
