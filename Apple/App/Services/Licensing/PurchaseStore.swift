import Foundation
import StoreKit
import gryonixNexusCore
#if os(iOS)
import UIKit
#endif

/// App Store purchases: products, buying, restoring, entitlement.
@MainActor
final class PurchaseStore: ObservableObject {
    static let shared = PurchaseStore()

    static let productIDs: [String: LicenseToken.Plan] = [
        "com.skaymer.gryonixnexus.license.monthly": .monthly,
        "com.skaymer.gryonixnexus.license.yearly": .yearly,
        "com.skaymer.gryonixnexus.license.lifetime": .lifetime,
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isWorking = false
    @Published var failure: String?

    private var updates: Task<Void, Never>?
    private var latestJWS: String?

    /// False for a Mac copy installed outside the App Store.
    static var isAvailable: Bool {
        #if os(macOS) && !DEBUG
        guard let receipt = Bundle.main.appStoreReceiptURL else { return false }
        return FileManager.default.fileExists(atPath: receipt.path)
        #else
        return true
        #endif
    }

    private init() {}

    func start() {
        guard Self.isAvailable, updates == nil else { return }
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await self?.refreshEntitlement()
            }
        }
        Task { await refreshEntitlement() }
    }

    func loadProducts() async {
        guard Self.isAvailable, products.isEmpty else { return }
        do {
            products = try await Product.products(for: Array(Self.productIDs.keys)).sorted { $0.price < $1.price }
        } catch {
            failure = error.localizedDescription
        }
    }

    func refreshEntitlement() async {
        var best: (plan: LicenseToken.Plan, expires: Date?, jws: String)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil,
                  let plan = Self.productIDs[transaction.productID] else { continue }
            if best == nil || plan == .lifetime {
                best = (plan, transaction.expirationDate, result.jwsRepresentation)
            }
        }
        latestJWS = best?.jws
        LicenseStore.shared.setAppStoreEntitlement(best?.plan, expires: best?.expires)
    }

    func purchase(_ product: Product) async {
        failure = nil
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshEntitlement()
            case .success(.unverified):
                failure = UIL10n.string("The purchase could not be verified.")
            case .pending:
                failure = UIL10n.string("The purchase is waiting for approval.")
            default:
                break
            }
        } catch {
            failure = error.localizedDescription
        }
    }

    func restore() async {
        failure = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !LicenseStore.shared.status.isActive {
                failure = UIL10n.string("This Apple Account has no gryonixNexus purchase.")
            }
        } catch {
            failure = error.localizedDescription
        }
    }

    /// The activation code for this Apple purchase, for other devices.
    func codeForOtherDevices() async throws -> String {
        if let code = LicenseStore.shared.code { return code }
        await refreshEntitlement()
        guard let jws = latestJWS else { throw LicenseAPI.Failure.rejected }
        guard let code = try await LicenseAPI.claimApple(jws: jws).code else { throw LicenseAPI.Failure.rejected }
        LicenseStore.shared.remember(code: code)
        return code
    }

    func openManageSubscriptions() {
        #if os(iOS)
        Task {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first else { return }
            try? await AppStore.showManageSubscriptions(in: scene)
        }
        #endif
    }
}
