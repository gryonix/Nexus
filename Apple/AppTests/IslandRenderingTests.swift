import XCTest
@testable import gryonixNexus
#if os(iOS)
import SwiftUI
import VPNTunnel

@MainActor
final class IslandRenderingTests: XCTestCase {
    private func model(_ style: VPNIslandStyle, armed: Bool = false) -> VPNIslandModel {
        VPNIslandModel(status: .connected(since: Date().addingTimeInterval(-3_754)),
                       statistics: TunnelStatistics(received: 1_480_300_000, sent: 83_100_000, lastHandshake: nil),
                       startedAt: Date().addingTimeInterval(-3_754),
                       serverName: "example.org", protocolName: "AmneziaWG", profileName: "iPhone",
                       isSimulated: false, style: style, stopArmed: armed)
    }

    private func render(_ view: some View, width: CGFloat, size: DynamicTypeSize) -> UIImage? {
        let renderer = ImageRenderer(content: view
            .frame(width: width)
            .padding(.vertical, 8)
            .background(Color(white: 0.85))
            .dynamicTypeSize(size))
        renderer.scale = 3
        return renderer.uiImage
    }

    func testEveryStyleFitsTheSmallestAndLargestPhones() throws {
        var styles: [(String, VPNIslandStyle, Bool)] = []
        for detail in VPNIslandStyle.CompactDetail.allCases {
            var style = VPNIslandStyle.standard
            style.compactDetail = detail
            styles.append((detail.rawValue, style, false))
        }
        var everything = VPNIslandStyle.standard
        everything.showsTraffic = true
        everything.tint = .status
        styles.append(("everything-armed", everything, true))
        let out = ProcessInfo.processInfo.environment["ISLAND_OUT"]
        for (name, style, armed) in styles {
            for (width, phone) in [(375.0, "mini"), (440.0, "promax")] {
                for size in [DynamicTypeSize.medium, .xxxLarge] {
                    let image = try XCTUnwrap(render(DynamicIslandPreview(model: model(style, armed: armed)),
                                                     width: width, size: size))
                    XCTAssertGreaterThan(image.size.height, 100, "\(name) did not draw")
                    if let out, let data = image.pngData() {
                        try data.write(to: URL(fileURLWithPath: "\(out)/\(name)-\(phone)-\(size).png"))
                    }
                }
            }
        }
    }
}
#endif

final class CompactBytesTests: XCTestCase {
    func testTheSmallIslandGetsAtMostFourCharacters() {
        XCTAssertEqual(CompactBytes.of(0), "0B")
        XCTAssertEqual(CompactBytes.of(1_480_300_000), "1.4G")
        XCTAssertEqual(CompactBytes.of(83_100_000), "79M")
        XCTAssertEqual(CompactBytes.of(512), "512B")
        XCTAssertLessThanOrEqual(CompactBytes.of(999_000_000_000).count, 4)
    }
}
