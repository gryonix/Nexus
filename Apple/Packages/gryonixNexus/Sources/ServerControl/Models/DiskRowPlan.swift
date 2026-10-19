import Foundation

public struct DiskRowPlan: Equatable, Sendable {
    public let primary: [DiskMount]
    public let namesPrimaryByTarget: Bool
    /// The rows behind the "Other volumes" disclosure
    public let others: [DiskMount]

    public init(primary: [DiskMount], namesPrimaryByTarget: Bool, others: [DiskMount]) {
        self.primary = primary
        self.namesPrimaryByTarget = namesPrimaryByTarget
        self.others = others
    }

    public static func make(mounts: [DiskMount]) -> DiskRowPlan {
        let root = mounts.first { $0.target == "/" }
        guard let root else {
            return DiskRowPlan(primary: mounts,
                               namesPrimaryByTarget: true,
                               others: [])
        }
        return DiskRowPlan(primary: [root],
                           namesPrimaryByTarget: false,
                           others: mounts.filter { $0.target != "/" })
    }
}
