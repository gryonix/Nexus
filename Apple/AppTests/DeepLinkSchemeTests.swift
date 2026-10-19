import VPNTunnel
import XCTest
@testable import gryonixNexus

final class DeepLinkSchemeTests: XCTestCase {
    private var declaredSchemes: [String] {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        return (types ?? []).flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
    }

    func testTheAppDeclaresTheSchemeAppLinkBuilds() {
        XCTAssertTrue(declaredSchemes.contains(AppLink.scheme),
                      "Info.plist declares \(declaredSchemes), AppLink builds \(AppLink.scheme)")
    }

    func testEveryDeclaredSchemeIsOneAppLinkAnswers() {
        for scheme in declaredSchemes {
            let url = URL(string: "\(scheme)://tunnel")!
            XCTAssertEqual(AppLink.destination(of: url), .tunnel,
                           "the app is registered for \(scheme):// but AppLink drops it")
        }
    }

    func testTheDeclarationIsNotEmpty() {
        XCTAssertFalse(declaredSchemes.isEmpty,
                       "no CFBundleURLTypes at all — every deep link is a dead button")
    }
}
