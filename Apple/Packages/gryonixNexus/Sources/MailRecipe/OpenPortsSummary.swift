import gryonixNexusCore
import ServiceCatalog

public struct OpenPortRequirement: Sendable, Hashable, Identifiable {
    public enum Proto: String, Sendable { case tcp = "TCP", udp = "UDP" }

    public let port: Int
    public let proto: Proto
    /// Who needs the port — "Mailcow (SMTP)", "SSH", … — joined when shared
    public let purpose: String

    public var id: String { "\(port)/\(proto.rawValue)" }

    public init(port: Int, proto: Proto, purpose: String) {
        self.port = port
        self.proto = proto
        self.purpose = purpose
    }
}

extension Array where Element == OpenPortRequirement {
    public func sortedByPort() -> [OpenPortRequirement] {
        sorted { ($0.port, $0.proto.rawValue) < ($1.port, $1.proto.rawValue) }
    }

    public func sortedByProtocol() -> [OpenPortRequirement] {
        sorted { ($0.proto.rawValue, $0.port) < ($1.proto.rawValue, $1.port) }
    }
}

public enum OpenPortsSummary {
    public static func entryHostPorts(for input: MailRecipeInput) -> [OpenPortRequirement] {
        let context = MailContext(input: input, renderer: StringTemplateRenderer())
        struct Key: Hashable {
            let port: Int
            let proto: OpenPortRequirement.Proto
        }
        var purposes: [Key: [String]] = [:]
        func add(_ port: Int, _ proto: OpenPortRequirement.Proto, _ purpose: String) {
            var list = purposes[Key(port: port, proto: proto)] ?? []
            if !list.contains(purpose) { list.append(purpose) }
            purposes[Key(port: port, proto: proto)] = list
        }

        add(input.security.ssh.port, .tcp, "SSH")
        if input.topology == .vpsRelayWithHomeBackend {
            add(WireGuardDefaults.listenPort, .udp, "WireGuard (VPS ↔ home)")
        }
        add(80, .tcp, "HTTP / ACME")
        if context.needsCaddy { add(443, .tcp, "HTTPS") }
        for service in context.allSelectedServices {
            for firewallPort in service.firewallPorts(context.serviceContext) {
                let proto: OpenPortRequirement.Proto = firewallPort.proto == .udp ? .udp : .tcp
                let purpose = firewallPort.comment.isEmpty || firewallPort.comment == service.displayName
                    ? service.displayName
                    : "\(service.displayName) (\(firewallPort.comment))"
                add(firewallPort.port, proto, purpose)
            }
        }

        return purposes
            .map { key, names in
                OpenPortRequirement(port: key.port, proto: key.proto,
                                    purpose: names.joined(separator: ", "))
            }
            .sorted { ($0.port, $0.proto.rawValue) < ($1.port, $1.proto.rawValue) }
    }
}
