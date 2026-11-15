import AgentClient
import Foundation

public struct DockerImageSummary: Sendable, Hashable, Identifiable {
    public let reference: String
    public let name: String
    public let sizeBytes: UInt64
    public let containers: Int
    public let createdSince: String
    public var id: String { reference }
    public var isInUse: Bool { containers > 0 }

    public init(reference: String, name: String, sizeBytes: UInt64, containers: Int, createdSince: String) {
        self.reference = reference
        self.name = name
        self.sizeBytes = sizeBytes
        self.containers = containers
        self.createdSince = createdSince
    }
}

public struct DockerVolumeSummary: Sendable, Hashable, Identifiable {
    public let name: String
    public let sizeBytes: UInt64
    public let containers: Int
    public let isManaged: Bool
    public var id: String { name }
    public var isInUse: Bool { containers > 0 }
    public var isRemovable: Bool { !isInUse && !isManaged }

    public init(name: String, sizeBytes: UInt64, containers: Int, isManaged: Bool) {
        self.name = name
        self.sizeBytes = sizeBytes
        self.containers = containers
        self.isManaged = isManaged
    }
}

public struct DockerNetworkSummary: Sendable, Hashable, Identifiable {
    public let name: String
    public let driver: String
    public let subnet: String
    public let containers: Int
    public let isManaged: Bool
    public let isBuiltin: Bool
    public let isInternal: Bool
    public var id: String { name }
    public var isInUse: Bool { containers > 0 }
    public var isRemovable: Bool { !isInUse && !isManaged && !isBuiltin }

    public init(name: String, driver: String, subnet: String, containers: Int,
                isManaged: Bool, isBuiltin: Bool, isInternal: Bool) {
        self.name = name
        self.driver = driver
        self.subnet = subnet
        self.containers = containers
        self.isManaged = isManaged
        self.isBuiltin = isBuiltin
        self.isInternal = isInternal
    }
}

public struct DockerPruneSummary: Sendable, Equatable {
    public let imagesRemoved: Int
    public let volumesRemoved: Int
    public let reclaimedBytes: UInt64
    public let failures: [String]

    public init(imagesRemoved: Int, volumesRemoved: Int, reclaimedBytes: UInt64, failures: [String]) {
        self.imagesRemoved = imagesRemoved
        self.volumesRemoved = volumesRemoved
        self.reclaimedBytes = reclaimedBytes
        self.failures = failures
    }
}

public enum DockerUsage {
    /// Bytes a prune of unused images and volumes would free
    public static func reclaimable(images: [DockerImageSummary], volumes: [DockerVolumeSummary]) -> UInt64 {
        images.filter { !$0.isInUse }.reduce(0) { $0 + $1.sizeBytes }
            + volumes.filter(\.isRemovable).reduce(0) { $0 + $1.sizeBytes }
    }

    public static func total(images: [DockerImageSummary], volumes: [DockerVolumeSummary]) -> UInt64 {
        images.reduce(0) { $0 + $1.sizeBytes } + volumes.reduce(0) { $0 + $1.sizeBytes }
    }
}

public protocol DockerAssetManaging: Sendable {
    func images() async throws -> [DockerImageSummary]
    func volumes() async throws -> [DockerVolumeSummary]
    func removeImage(_ reference: String) async throws
    func removeVolume(_ name: String) async throws
    func pruneUnused(images: Bool, volumes: Bool) async throws -> DockerPruneSummary
    func networks() async throws -> [DockerNetworkSummary]
    func removeNetwork(_ name: String) async throws
}

extension DockerAssetManaging {
    public func networks() async throws -> [DockerNetworkSummary] { [] }
    public func removeNetwork(_ name: String) async throws {}
}

public struct DockerAssetError: Error, LocalizedError, Equatable {
    public let message: String
    public var errorDescription: String? { message }

    public init(message: String) { self.message = message }
}

@available(macOS 15.0, *)
public struct AgentDockerAssets: DockerAssetManaging {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    public func images() async throws -> [DockerImageSummary] {
        let client = self.client
        let wire = try await run { try await client.listImages() }
        if !wire.unavailableReason.isEmpty { throw DockerAssetError(message: wire.unavailableReason) }
        return wire.images.map {
            DockerImageSummary(reference: $0.reference,
                               name: $0.repository.isEmpty || $0.repository == "<none>" ? $0.id : "\($0.repository):\($0.tag)",
                               sizeBytes: $0.sizeBytes, containers: Int($0.containers),
                               createdSince: $0.createdSince)
        }
    }

    public func volumes() async throws -> [DockerVolumeSummary] {
        let client = self.client
        let wire = try await run { try await client.listVolumes() }
        if !wire.unavailableReason.isEmpty { throw DockerAssetError(message: wire.unavailableReason) }
        return wire.volumes.map {
            DockerVolumeSummary(name: $0.name, sizeBytes: $0.sizeBytes,
                                containers: Int($0.containers), isManaged: $0.managed)
        }
    }

    public func removeImage(_ reference: String) async throws {
        let client = self.client
        try Self.check(try await run { try await client.removeImage(reference: reference) })
    }

    public func removeVolume(_ name: String) async throws {
        let client = self.client
        try Self.check(try await run { try await client.removeVolume(name: name) })
    }

    public func pruneUnused(images: Bool, volumes: Bool) async throws -> DockerPruneSummary {
        let client = self.client
        let wire = try await run { try await client.pruneUnused(images: images, volumes: volumes) }
        return DockerPruneSummary(imagesRemoved: Int(wire.imagesRemoved), volumesRemoved: Int(wire.volumesRemoved),
                                  reclaimedBytes: wire.reclaimedBytes, failures: wire.failures)
    }

    public func networks() async throws -> [DockerNetworkSummary] {
        let client = self.client
        let wire = try await run { try await client.listNetworks() }
        if !wire.unavailableReason.isEmpty { throw DockerAssetError(message: wire.unavailableReason) }
        return wire.networks.map {
            DockerNetworkSummary(name: $0.name, driver: $0.driver, subnet: $0.subnet, containers: Int($0.containers),
                                 isManaged: $0.managed, isBuiltin: $0.builtin, isInternal: $0.internal)
        }
    }

    public func removeNetwork(_ name: String) async throws {
        let client = self.client
        try Self.check(try await run { try await client.removeNetwork(name: name) })
    }

    private static func check(_ result: Gryonixnexusd_V1_DockerRemovalResult) throws {
        if !result.removed { throw DockerAssetError(message: result.message) }
    }

    private func run<T: Sendable>(_ call: @escaping @Sendable () async throws -> T) async throws -> T {
        if let gate { return try await gate.withSlot(call) }
        return try await call()
    }
}
