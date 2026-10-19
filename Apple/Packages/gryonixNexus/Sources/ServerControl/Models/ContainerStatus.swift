/// One row of `docker compose ps` / `docker ps -a`: container name + raw status.
public struct ContainerStatus: Sendable, Hashable {
    public let name: String
    /// Verbatim STATUS column, e.g
    public let status: String

    public init(name: String, status: String) {
        self.name = name
        self.status = status
    }

    public var health: HealthLevel {
        let lowered = status.lowercased()
        if lowered.contains("not running") || lowered.contains("no such container") {
            return .warning
        }
        if lowered.contains("unhealthy") { return .critical }
        if lowered.hasPrefix("up") || lowered.contains("running") { return .ok }
        if lowered.contains("exit") { return .critical }
        return .warning
    }
}
