import UIKit
import XCTest

@testable import gryonixNexus

final class AppIconTests: XCTestCase {
    func testEveryOfferedIconIsDeclaredByTheBundle() throws {
        let icons = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let alternates = try XCTUnwrap(icons["CFBundleAlternateIcons"] as? [String: Any])
        for choice in AppIconChoice.allCases {
            guard let name = choice.assetName else { continue }
            XCTAssertNotNil(alternates[name],
                            "\(choice.rawValue) is offered in Appearance, so \(name) has to be in ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES")
        }
    }

    func testTheColoursMatchTheDefaultIconsGeometry() throws {
        let reference = try inkBox(named: "gryonixNexus60x60@2x")
        for choice in AppIconChoice.allCases {
            let image = try XCTUnwrap(UIImage(named: choice.previewName), choice.previewName)
            let box = try inkBox(of: image)
            XCTAssertEqual(box.width, reference.width, accuracy: 0.02, "width of \(choice.rawValue)")
            XCTAssertEqual(box.height, reference.height, accuracy: 0.02, "height of \(choice.rawValue)")
            XCTAssertEqual(box.minX, reference.minX, accuracy: 0.02, "left margin of \(choice.rawValue)")
            XCTAssertEqual(box.minY, reference.minY, accuracy: 0.02, "top margin of \(choice.rawValue)")
        }
    }

    private func inkBox(of image: UIImage) throws -> CGRect {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let red = Int(pixels[index]), green = Int(pixels[index + 1])
                let blue = Int(pixels[index + 2]), alpha = Int(pixels[index + 3])
                let distanceFromWhite = (255 - red) * (255 - red)
                    + (255 - green) * (255 - green) + (255 - blue) * (255 - blue)
                if alpha > 40 && distanceFromWhite > 90 * 90 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY else {
            XCTFail("no artwork found in the image")
            return .zero
        }
        return CGRect(x: CGFloat(minX) / CGFloat(width), y: CGFloat(minY) / CGFloat(height),
                      width: CGFloat(maxX - minX + 1) / CGFloat(width),
                      height: CGFloat(maxY - minY + 1) / CGFloat(height))
    }

    private func inkBox(named name: String) throws -> CGRect {
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "png"),
                                "\(name).png is the icon Xcode rendered from the Icon Composer bundle; without it there is nothing to compare against")
        let image = try XCTUnwrap(UIImage(data: try Data(contentsOf: url)))
        return try inkBox(of: image)
    }
}

final class AppAccentOrderTests: XCTestCase {
    /// The colours, in the order each list offers them
    private var iconColours: [String] {
        AppIconChoice.allCases.map(\.rawValue).filter { $0 != AppIconChoice.default.rawValue }
    }

    private var accentColours: [String] {
        AppAccentChoice.allCases
            .map(\.rawValue)
            .filter { $0 != AppAccentChoice.app.rawValue && $0 != AppAccentChoice.matchesIcon.rawValue }
    }

    func testTheAccentListStartsWithTheRowThatNamesTheIcon() {
        XCTAssertEqual(AppAccentChoice.allCases.first, .matchesIcon,
                       "the accent list no longer opens with Match icon")
        XCTAssertEqual(AppAccentChoice.allCases.dropFirst().first, .app,
                       "the app's own accent is no longer the second answer")
    }

    func testTheColoursRunInTheIconGridsOrder() {
        XCTAssertEqual(accentColours, iconColours,
                       "the accent colours and the icon colours are offered in different orders — "
                       + "one of the two lists gained or moved a colour")
    }

    func testNeitherListOffersAColourTheOtherDoesNot() {
        XCTAssertEqual(Set(accentColours), Set(iconColours))
    }
}
