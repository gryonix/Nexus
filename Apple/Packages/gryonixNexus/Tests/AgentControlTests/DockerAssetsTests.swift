import XCTest
@testable import AgentControl

final class DockerAssetsTests: XCTestCase {
    private let images = [
        DockerImageSummary(reference: "a:1", name: "a:1", sizeBytes: 100, containers: 1, createdSince: ""),
        DockerImageSummary(reference: "b:1", name: "b:1", sizeBytes: 40, containers: 0, createdSince: ""),
    ]
    private let volumes = [
        DockerVolumeSummary(name: "used", sizeBytes: 10, containers: 2, isManaged: false),
        DockerVolumeSummary(name: "managed", sizeBytes: 20, containers: 0, isManaged: true),
        DockerVolumeSummary(name: "free", sizeBytes: 5, containers: 0, isManaged: false),
    ]

    func testOnlyUnusedUnmanagedVolumesAreRemovable() {
        XCTAssertEqual(volumes.filter(\.isRemovable).map(\.name), ["free"])
    }

    func testReclaimableCountsUnusedImagesAndFreeVolumes() {
        XCTAssertEqual(DockerUsage.reclaimable(images: images, volumes: volumes), 45)
        XCTAssertEqual(DockerUsage.total(images: images, volumes: volumes), 175)
    }
}
