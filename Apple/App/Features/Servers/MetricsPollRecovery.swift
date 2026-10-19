import ServerControl

enum MetricsPollRecovery: Equatable {
    /// A clean tick: keep everything
    case none
    /// The entry host missed the tick
    case rebuildRunner
    /// Only machines behind the entry host missed it
    case dropLinks([SSHHostID])

    static func after(failed: [SSHHostID], entry: SSHHostID = .vps) -> MetricsPollRecovery {
        if failed.contains(entry) { return .rebuildRunner }
        return failed.isEmpty ? .none : .dropLinks(failed)
    }
}
