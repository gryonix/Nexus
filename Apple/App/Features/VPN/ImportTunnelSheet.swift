import ServiceCatalog
import SwiftUI
import UniformTypeIdentifiers
import VPNProfile
import VPNTunnel
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Adds a tunnel from a configuration of another server
struct ImportTunnelSheet: View {
    @ObservedObject var tunnel: TunnelController
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var name = ""
    /// The name stops following the suggestion once typed
    @State private var nameTyped = false
    @State private var choosingFile = false
    @State private var scanning = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                configurationSection
                if scanning { scannerSection }
                nameSection
            }
            .formStyle(.grouped)
            .screenTitle("Add a configuration")
            .toolbar { toolbar }
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.data, .text]) { read($0) }
            .onChange(of: detected?.suggestedName) { _, suggested in
                if !nameTyped, let suggested { name = suggested }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
    }

    private var detection: Result<ForeignTunnelConfig.Detected, Error> {
        Result { try ForeignTunnelConfig.detect(text) }
    }

    private var detected: ForeignTunnelConfig.Detected? { try? detection.get() }

    /// How many servers VPN Advanced would take
    private var advancedCount: Int? {
        guard detected == nil, !text.isEmpty else { return nil }
        return ImportTunnelText.advancedServers(in: text)
    }

    private var configurationSection: some View {
        Section {
            TextEditor(text: $text)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 150)
                .autocorrectionDisabled()
                #if os(iOS) || os(tvOS)
                .textInputAutocapitalization(.never)
                #endif
            ImportTunnelSources(scanning: $scanning, onPaste: paste, onChooseFile: { choosingFile = true })
        } header: {
            InfoSectionHeader("Configuration", note: "A WireGuard or AmneziaWG file, an Amnezia vpn:// key, or an ss:// or vless:// link. The tunnel is used as it is; the app does not manage its server.")
        } footer: {
            ImportTunnelVerdict(detection: text.isEmpty ? nil : detection, advancedCount: advancedCount,
                                saveError: saveError)
        }
    }

    private var scannerSection: some View {
        Section {
            QuickTransferScannerView(imageProblemText: "That image holds no configuration.") { code in
                guard (try? ForeignTunnelConfig.detect(code)) != nil
                        || ImportTunnelText.advancedServers(in: code) != nil else { return false }
                text = code
                scanning = false
                return true
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var nameSection: some View {
        Section("Name") {
            TextField("Name", text: Binding(get: { name }, set: { name = $0; nameTyped = true }))
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Add") { add() }
                .disabled(detected == nil && advancedCount == nil)
                .accessibilityIdentifier("import.add")
        }
    }

    private func add() {
        if advancedCount != nil {
            AdvancedVPNModel.shared.importText(text)
            dismiss()
            return
        }
        guard let detected else { return }
        do {
            try tunnel.importForeign(detected, name: name)
            dismiss()
        } catch {
            saveError = VPNText.message(for: error)
        }
    }

    private func paste() {
        #if os(macOS)
        if let pasted = NSPasteboard.general.string(forType: .string) { text = pasted }
        #elseif os(iOS)
        if let pasted = UIPasteboard.general.string { text = pasted }
        #endif
    }

    private func read(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count < 1_000_000,
              let contents = String(data: data, encoding: .utf8) else { return }
        text = contents
        if !nameTyped { name = url.deletingPathExtension().lastPathComponent; nameTyped = true }
    }
}

/// Paste, file and camera, side by side
private struct ImportTunnelSources: View {
    @Binding var scanning: Bool
    let onPaste: () -> Void
    let onChooseFile: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Button(action: onPaste) { Label("Paste", systemImage: "doc.on.clipboard") }
            Button(action: onChooseFile) { Label("Choose a file", systemImage: "folder") }
            #if os(iOS) || os(tvOS)
            Button { scanning.toggle() } label: { Label("Scan a QR code", systemImage: "qrcode.viewfinder") }
            #endif
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .font(.title3)
    }
}

/// What the pasted text turned out to be
private struct ImportTunnelVerdict: View {
    let detection: Result<ForeignTunnelConfig.Detected, Error>?
    let advancedCount: Int?
    let saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else if let advancedCount {
                Label(UIL10n.string("Servers for VPN Advanced: %lld", advancedCount), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("These servers are added to the VPN Advanced list. Turn on VPN Advanced in Settings → Modules to use them.")
            } else if let detection {
                verdict(detection)
            }
        }
    }

    @ViewBuilder
    private func verdict(_ detection: Result<ForeignTunnelConfig.Detected, Error>) -> some View {
        switch detection {
        case .success(let found):
            Label(ServiceRegistry.service(found.protocolID)?.displayName ?? found.protocolID.rawValue,
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let error):
            Label(ImportTunnelText.failure(error), systemImage: "xmark.circle")
                .foregroundStyle(.orange)
        }
    }
}

enum ImportTunnelText {
    /// Servers a list, a link or a Clash profile holds
    static func advancedServers(in text: String) -> Int? {
        let count = SubscriptionImport.parse(body: text).servers.count
        return count > 0 ? count : nil
    }

    static func failure(_ error: Error) -> String {
        switch error as? ForeignTunnelConfig.Failure {
        case .notCarried(let protocolID):
            return UIL10n.string("This app cannot bring up %@ tunnels yet.",
                                 ServiceRegistry.service(protocolID)?.displayName ?? protocolID.rawValue)
        case .unreadable: return UIL10n.string("The configuration could not be read.")
        case .empty: return UIL10n.string("Paste or choose a configuration first.")
        default: return UIL10n.string("This is not a VPN configuration the app knows.")
        }
    }
}
