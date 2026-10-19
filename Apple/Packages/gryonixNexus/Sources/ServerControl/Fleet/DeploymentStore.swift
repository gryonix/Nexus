import Foundation

/// Persistence of the deployment list
public protocol DeploymentStore: Sendable {
    func load() throws -> [Deployment]
    func save(_ deployments: [Deployment]) throws
}

public struct FileDeploymentStore: DeploymentStore {
    private let fileURL: URL

    /// Default location: Application Support/gryonixNexus/deployments.json
    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
            let directory = support.appendingPathComponent("gryonixNexus", isDirectory: true)
            AppSupportDirectory.adoptLegacyName(at: directory, legacyName: "GryonixNexus")
            self.fileURL = directory.appendingPathComponent("deployments.json")
        }
    }

    public func load() throws -> [Deployment] {
        try DeploymentStoreLock.run {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
            return try DeploymentListCodec.decode(Data(contentsOf: fileURL))
        }
    }

    public func save(_ deployments: [Deployment]) throws {
        try DeploymentStoreLock.run {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let unreadable = (try? Data(contentsOf: fileURL))
                .flatMap { try? DeploymentListCodec.decodeLossy($0).unreadable } ?? []
            try DeploymentListCodec.encode(deployments, keeping: unreadable).write(to: fileURL, options: .atomic)
        }
    }
}

/// One lock for every read-modify-write of the server list
public enum DeploymentStoreLock {
    private static let lock = NSRecursiveLock()

    public static func run<T>(_ work: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
    }
}

extension DeploymentStore {
    /// Insert-or-replace by id
    public func upsert(_ deployment: Deployment) throws {
        try DeploymentStoreLock.run {
            var deployments = try load()
            if let index = deployments.firstIndex(where: { $0.id == deployment.id }) {
                deployments[index] = deployment
            } else {
                deployments.append(deployment)
            }
            try save(deployments)
        }
    }

    @discardableResult
    public func update(id: UUID, _ change: (inout Deployment) -> Void) throws -> Bool {
        try DeploymentStoreLock.run {
            var all = try load()
            guard let index = all.firstIndex(where: { $0.id == id }) else { return false }
            change(&all[index])
            try save(all)
            return true
        }
    }

    /// Removes the deployment from the list
    public func remove(id: UUID) throws {
        try DeploymentStoreLock.run { try save(try load().filter { $0.id != id }) }
    }
}
