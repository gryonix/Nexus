import AgentControl
import Foundation
import ServerControl

@available(macOS 15.0, *)
@MainActor
final class DockerAssetsViewModel: ObservableObject {
    @Published private(set) var images: [DockerImageSummary] = []
    @Published private(set) var volumes: [DockerVolumeSummary] = []
    @Published private(set) var networks: [DockerNetworkSummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published private(set) var notice: String?

    private let deployment: Deployment
    private let make: (Deployment) async throws -> any DockerAssetManaging

    init(deployment: Deployment,
         make: @escaping (Deployment) async throws -> any DockerAssetManaging = DockerAssetsViewModel.agent) {
        self.deployment = deployment
        self.make = make
    }

    static func agent(_ deployment: Deployment) async throws -> any DockerAssetManaging {
        let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: deployment)
        let client = try await AgentConnection.client(deployment: deployment, runner: runner)
        return AgentDockerAssets(client: client, gate: AgentChannelGate.shared(for: deployment.id))
    }

    var reclaimableBytes: UInt64 { DockerUsage.reclaimable(images: images, volumes: volumes) }
    var totalBytes: UInt64 { DockerUsage.total(images: images, volumes: volumes) }
    var hasUnused: Bool { images.contains { !$0.isInUse } || volumes.contains(where: \.isRemovable) }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await attempt {
            let assets = try await self.make(self.deployment)
            async let loadedImages = assets.images()
            async let loadedVolumes = assets.volumes()
            async let loadedNetworks = assets.networks()
            self.images = try await loadedImages
            self.volumes = try await loadedVolumes
            self.networks = (try? await loadedNetworks) ?? []
        }
    }

    func removeImage(_ image: DockerImageSummary) async {
        await change { try await $0.removeImage(image.reference) }
    }

    func removeVolume(_ volume: DockerVolumeSummary) async {
        await change { try await $0.removeVolume(volume.name) }
    }

    func removeNetwork(_ network: DockerNetworkSummary) async {
        await change { try await $0.removeNetwork(network.name) }
    }

    func pruneUnused() async {
        await change { assets in
            let summary = try await assets.pruneUnused(images: true, volumes: true)
            self.notice = Self.noticeText(summary)
            if !summary.failures.isEmpty { throw DockerAssetError(message: summary.failures.joined(separator: "\n")) }
        }
    }

    static func noticeText(_ summary: DockerPruneSummary) -> String {
        UIL10n.string("Removed %lld images and %lld volumes, %@ freed.", summary.imagesRemoved,
                      summary.volumesRemoved,
                      ByteCountFormatter.string(fromByteCount: Int64(summary.reclaimedBytes), countStyle: .file))
    }

    private func change(_ body: @escaping (any DockerAssetManaging) async throws -> Void) async {
        isWorking = true
        notice = nil
        defer { isWorking = false }
        await attempt { try await body(try await self.make(self.deployment)) }
        let failure = errorMessage
        await load()
        if failure != nil { errorMessage = failure }
    }

    private func attempt(_ body: () async throws -> Void) async {
        do {
            try await body()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? DashboardViewModel.message(for: error)
        }
    }
}
