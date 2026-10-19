import ServerControl

extension Deployment {
    func metricsMachineLabel(for host: SSHHostID) -> String? {
        guard nodes.count > 1 else { return nil }
        guard let node = nodes.first(where: { $0.sshHost == host }) else {
            switch host.kind {
            case .slot(.home): return UIL10n.string("Local")
            default: return UIL10n.string("VPS")
            }
        }
        if !node.name.isEmpty { return node.name }
        switch node.legacySlot {
        case .vps: return UIL10n.string("VPS")
        case .home: return UIL10n.string("Local")
        case nil: return node.endpoint.host
        }
    }
}
