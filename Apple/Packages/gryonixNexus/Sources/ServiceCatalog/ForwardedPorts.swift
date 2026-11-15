/// The ports a relay carries in from the internet
public enum ForwardedPorts {
    /// DNS serves the home network, never the internet
    static let homeOnlyPorts: Set<Int> = [53]

    public static func tcp(services: [any ManagedService], context: ServiceContext,
                           excluding: Set<String> = []) -> [Int] {
        var ports: Set<Int> = [80]
        if services.contains(where: { $0.webIngress(context).map { !$0.homeOnly } ?? false }) {
            ports.insert(443)
        }
        ports.formUnion(carried(services, context, .tcp, excluding))
        return ports.sorted()
    }

    public static func udp(services: [any ManagedService], context: ServiceContext,
                           excluding: Set<String> = []) -> [Int] {
        carried(services, context, .udp, excluding).sorted()
    }

    /// A service's own TCP ports, without the shared web ports
    public static func ownTCP(of service: any ManagedService, context: ServiceContext) -> [Int] {
        tcp(services: [service], context: context).filter { $0 != 80 && $0 != 443 }
    }

    private static func carried(_ services: [any ManagedService], _ context: ServiceContext,
                                _ proto: FirewallPort.Proto, _ excluding: Set<String>) -> Set<Int> {
        var ports: Set<Int> = []
        for service in services where !service.requiresHomeMachine && !excluding.contains(service.id.rawValue) {
            for port in service.firewallPorts(context) where port.proto == proto && !homeOnlyPorts.contains(port.port) {
                ports.insert(port.port)
            }
        }
        return ports
    }
}

/// Ports the agent keeps to private addresses
public enum HomeOnlyPorts {
    /// Own ports of home-only services, without web ports
    public static func of(_ services: [any ManagedService], context: ServiceContext) -> [FirewallPort] {
        var seen = Set<String>()
        return services.flatMap { $0.firewallPorts(context) }
            .filter { $0.port != 80 && $0.port != 443 }
            .filter { seen.insert("\($0.proto.rawValue)/\($0.port)").inserted }
            .sorted { ($0.port, $0.proto.rawValue) < ($1.port, $1.proto.rawValue) }
    }
}
