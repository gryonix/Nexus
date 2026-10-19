import Foundation

public enum DeploymentListCodec {
    public static func encode(_ deployments: [Deployment]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(deployments)
    }

    /// The list, with entries that cannot be read skipped
    public static func decode(_ data: Data) throws -> [Deployment] {
        try decodeLossy(data).deployments
    }

    public static func decodeLossy(_ data: Data) throws -> (deployments: [Deployment], unreadable: [Any]) {
        if let all = try? JSONDecoder().decode([Deployment].self, from: data) { return (all, []) }
        guard let items = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            return (try JSONDecoder().decode([Deployment].self, from: data), [])
        }
        var readable: [Deployment] = []
        var unreadable: [Any] = []
        for item in items {
            let one = try? JSONSerialization.data(withJSONObject: item)
            if let one, let deployment = try? JSONDecoder().decode(Deployment.self, from: one) {
                readable.append(deployment)
            } else {
                unreadable.append(item)
            }
        }
        return (readable, unreadable)
    }

    public static func encode(_ deployments: [Deployment], keeping unreadable: [Any]) throws -> Data {
        guard !unreadable.isEmpty else { return try encode(deployments) }
        let known = Set(deployments.map { $0.id.uuidString.lowercased() })
        let kept = unreadable.filter { item in
            guard let id = (item as? [String: Any])?["id"] as? String else { return true }
            return !known.contains(id.lowercased())
        }
        let encoded = try JSONSerialization.jsonObject(with: try encode(deployments)) as? [Any] ?? []
        return try JSONSerialization.data(withJSONObject: encoded + kept, options: [.prettyPrinted, .sortedKeys])
    }
}
