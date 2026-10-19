import StoreKit
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The three plans: App Store, or the website outside it.
struct LicensePlansSection: View {
    @ObservedObject private var store = PurchaseStore.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            if PurchaseStore.isAvailable {
                ForEach(store.products, id: \.id) { product in
                    PlanRow(product: product)
                }
                if store.products.isEmpty { ProgressView() }
            } else {
                Button {
                    openURL(URL(string: "https://gryonix.com/buy")!)
                } label: {
                    Label("Buy on gryonix.com", systemImage: "cart")
                }
            }
            if let failure = store.failure {
                Text(failure).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Buy")
        }
        .task { await store.loadProducts() }
    }
}

private struct PlanRow: View {
    let product: Product
    @ObservedObject private var store = PurchaseStore.shared

    var body: some View {
        Button {
            Task { await store.purchase(product) }
        } label: {
            HStack {
                Text(LicenseStatusSection.planName(PurchaseStore.productIDs[product.id] ?? .monthly))
                Spacer()
                Text(product.displayPrice).fontWeight(.semibold)
            }
            .contentShape(Rectangle())
        }
        .disabled(store.isWorking)
    }
}

/// Restore: App Store sync, or an iPhone approving this Mac.
struct LicenseRestoreSection: View {
    @ObservedObject private var store = PurchaseStore.shared
    @ObservedObject private var license = LicenseStore.shared

    var body: some View {
        Section {
            if PurchaseStore.isAvailable {
                Button {
                    Task { await store.restore() }
                } label: {
                    Label("Restore Apple purchases", systemImage: "arrow.clockwise")
                }
                .disabled(store.isWorking)
            } else {
                NavigationLink {
                    MacPairingView()
                } label: {
                    Label("Restore Apple purchases with iPhone", systemImage: "iphone.and.arrow.forward")
                }
            }
            if case .active(_, _, true) = license.status { AppStoreExtras() }
        }
    }
}

private struct AppStoreExtras: View {
    @ObservedObject private var store = PurchaseStore.shared
    @State private var code: String?
    @State private var failure: String?

    var body: some View {
        #if os(iOS)
        Button("Manage subscription") { store.openManageSubscriptions() }
        #endif
        Button {
            Task { await reveal() }
        } label: {
            Label("Code for Android and Mac", systemImage: "key")
        }
        if let code { CopyableCode(code: code) }
        if let failure { Text(failure).font(.footnote).foregroundStyle(.red) }
    }

    private func reveal() async {
        do {
            code = try await store.codeForOtherDevices()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

struct CopyableCode: View {
    let code: String

    var body: some View {
        HStack {
            Text(verbatim: code).font(.body.monospaced()).textSelection(.enabled)
            Spacer()
            Button {
                copy()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Copy"))
        }
    }

    private func copy() {
        #if os(iOS)
        UIPasteboard.general.string = code
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #endif
    }
}
