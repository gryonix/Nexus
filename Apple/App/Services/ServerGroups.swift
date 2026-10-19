import Foundation
import ServerControl

enum ServerGroups {
    static func known(in deployments: [Deployment]) -> [String] {
        Array(Set(deployments.flatMap(\.tags))).sorted()
    }

    static func known() -> [String] {
        known(in: (try? FileDeploymentStore().load()) ?? [])
    }

    static func setting(_ member: Bool, of group: String, in tags: [String]) -> [String] {
        var result = tags.filter { $0.caseInsensitiveCompare(group) != .orderedSame }
        if member { result.append(group) }
        return result
    }

    /// Every server that carries this group
    static func members(of group: String, in deployments: [Deployment]) -> [Deployment] {
        deployments.filter { $0.tags.contains { $0.caseInsensitiveCompare(group) == .orderedSame } }
    }

    static func clean(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
