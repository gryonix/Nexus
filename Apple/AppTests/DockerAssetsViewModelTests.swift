import AgentControl
import ServerControl
import XCTest
@testable import gryonixNexus

@available(macOS 15.0, *)
@MainActor
final class DockerAssetsViewModelTests: XCTestCase {
    private actor Engine: DockerAssetManaging {
        var imageList = [DockerImageSummary(reference: "old:1", name: "old:1", sizeBytes: 50, containers: 0, createdSince: "")]
        var volumeList = [DockerVolumeSummary(name: "keep", sizeBytes: 9, containers: 0, isManaged: true)]
        var refuse = false

        func images() async throws -> [DockerImageSummary] { imageList }
        func volumes() async throws -> [DockerVolumeSummary] { volumeList }

        func removeImage(_ reference: String) async throws {
            if refuse { throw DockerAssetError(message: "a container still uses this image") }
            imageList.removeAll { $0.reference == reference }
        }

        func removeVolume(_ name: String) async throws {}

        func pruneUnused(images: Bool, volumes: Bool) async throws -> DockerPruneSummary {
            imageList = []
            return DockerPruneSummary(imagesRemoved: 1, volumesRemoved: 0, reclaimedBytes: 50, failures: [])
        }

        func refuseRemovals() { refuse = true }
    }

    private func model(_ engine: Engine) -> DockerAssetsViewModel {
        let deployment = Deployment(name: "orion", topology: .singleHost, domain: "example.net",
                                    entry: HostEndpoint(host: "203.0.113.5", user: "root"))
        return DockerAssetsViewModel(deployment: deployment) { _ in engine }
    }

    func testLoadThenRemoveRefreshesTheList() async {
        let engine = Engine()
        let model = model(engine)
        await model.load()
        XCTAssertEqual(model.images.count, 1)
        XCTAssertTrue(model.hasUnused)
        await model.removeImage(model.images[0])
        XCTAssertTrue(model.images.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testARefusalIsShownAndTheListIsKept() async {
        let engine = Engine()
        await engine.refuseRemovals()
        let model = model(engine)
        await model.load()
        await model.removeImage(model.images[0])
        XCTAssertEqual(model.errorMessage, "a container still uses this image")
        XCTAssertEqual(model.images.count, 1)
    }

    func testPruneReportsWhatWasFreed() async {
        let engine = Engine()
        let model = model(engine)
        await model.load()
        await model.pruneUnused()
        XCTAssertNotNil(model.notice)
        XCTAssertTrue(model.images.isEmpty)
    }
}
