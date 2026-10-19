import XCTest
@testable import ServiceCatalog

final class ServiceCategoryTests: XCTestCase {
    func testTheMeshShelfKeepsTheMemberThatCanWorkAnywhere() {
        XCTAssertTrue(ServiceCategory.selectable.contains(.mesh),
                      "the shelf must be in the list both forms render")
        XCTAssertEqual(ServiceRegistry.services(in: .mesh).map(\.id), [.headscale, .tailscaleNode])

        let onPublic = ServiceRegistry.services(in: .mesh, scope: .publicInternet).map(\.id)
        XCTAssertEqual(onPublic, [.headscale, .tailscaleNode], "both engines belong on a public deployment")

        let onLocal = ServiceRegistry.services(in: .mesh, scope: .localOnly).map(\.id)
        XCTAssertEqual(onLocal, [.tailscaleNode],
                       "the control server cannot work here; joining Tailscale can")
    }

    func testEveryServiceDeclaresAKnownCategory() {
        let known = Set(ServiceCategory.selectable + [.implicit])
        for service in ServiceRegistry.all {
            XCTAssertTrue(known.contains(service.category),
                          "\(service.id.rawValue) sits on an unknown shelf")
        }
    }

    func testTheImplicitShelfHoldsOnlyImpliedServices() {
        let implicit = ServiceRegistry.all.filter { $0.category == .implicit }.map(\.id)
        XCTAssertEqual(implicit, [.vpnPanel, .craftyController])
    }

    func testImplicitServicesDisplayUnderTheShelfThatBroughtThemIn() {
        XCTAssertEqual(ServiceRegistry.service(.vpnPanel)?.displayCategory, .vpn)
        XCTAssertEqual(ServiceRegistry.service(.craftyController)?.displayCategory, .games)
        for service in ServiceRegistry.all where service.category != .implicit {
            XCTAssertEqual(service.displayCategory, service.category,
                           "\(service.id.rawValue) is pickable, so its row belongs on its own shelf")
        }
    }

    func testCategoriesAreOfferedInTheirDeclaredOrder() {
        let categories = ServiceRegistry.categories
        XCTAssertEqual(categories, categories.sorted())
        XCTAssertEqual(categories.first, .ai)
        XCTAssertEqual(categories.dropFirst().first, .mail)
        XCTAssertFalse(categories.contains(.implicit))
        for category in categories {
            XCTAssertFalse(ServiceRegistry.services(in: category).isEmpty,
                           "\(category.id) is offered but holds nothing")
        }
    }

    func testExclusiveCategoriesProduceSymmetricConflicts() {
        for category in ServiceCategory.selectable
        where category.selection == .exclusive {
            let ids = ServiceRegistry.ids(in: category)
            for id in ids {
                XCTAssertEqual(ServiceRegistry.service(id)?.conflicts, ids.subtracting([id]),
                               "\(id.rawValue) must conflict with every other member of \(category.id)")
            }
        }
    }

    func testNonExclusiveCategoriesDeclareNoConflicts() {
        for service in ServiceRegistry.all where service.category.selection != .exclusive {
            XCTAssertTrue(service.conflicts.isEmpty,
                          "\(service.id.rawValue) is not on an exclusive shelf")
        }
    }

    func testTheFirstMemberOfEachCategoryIsTheDefaultChoice() {
        XCTAssertEqual(ServiceRegistry.services(in: .code).first?.id, .forgejo)
        XCTAssertEqual(ServiceRegistry.services(in: .vpn).first?.id, .wireguardVPN)
        XCTAssertEqual(ServiceRegistry.services(in: .mail).first?.id, .mailcow)
        XCTAssertEqual(ServiceRegistry.services(in: .files).first?.id, .nextcloud)
        XCTAssertEqual(ServiceRegistry.services(in: .photos).first?.id, .immich)
    }

    func testSelectionReportsWhatACategoryInstalls() {
        let selection: Set<ServiceID> = [.dockerMailserver, .vaultwarden, .wireguardVPN]
        XCTAssertEqual(ServiceRegistry.selection(in: .mail, from: selection), [.dockerMailserver])
        XCTAssertEqual(ServiceRegistry.selection(in: .passwords, from: selection), [.vaultwarden])
        XCTAssertEqual(ServiceRegistry.selection(in: .photos, from: selection), [])
    }

    func testServicesThatNameAnAdminAccountDeclareIt() {
        let declared = Set(ServiceRegistry.all.filter(\.usesSharedAdminLogin).map(\.id))
        XCTAssertEqual(declared, [.nextcloud, .seafile, .psono, .forgejo, .gitlab, .mailu,
                                  .dockerMailserver, .adguardHome, .photoprism, .vpnPanel,
                                  .authelia])
    }
}
