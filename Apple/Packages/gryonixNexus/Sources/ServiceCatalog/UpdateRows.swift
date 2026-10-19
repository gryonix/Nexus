public enum UpdateRows {
    public static func statusRows(
        updatable: [ServiceID],
        deploymentServices: Set<ServiceID>,
        reported: some Sequence<ServiceID>
    ) -> [ServiceID] {
        let own = Set(updatable)
        let extra = reported
            .filter { !deploymentServices.contains($0) && !own.contains($0) }
            .sorted { $0.rawValue < $1.rawValue }
        return updatable + extra
    }
}
