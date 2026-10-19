import AgentControl
import CoreImage
import CoreImage.CIFilterBuiltins
import ServerControl
import ServiceCatalog
import SwiftUI
import VPNProfile
import VPNTunnel
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Naming a new device
struct VPNClientNameSheet: View {
    /// Set for VLESS / Reality: the site its handshake imitates now
    var currentSite: String?
    var protocolID: ServiceID = .wireguardVPN
    var defaultDNS: [String] = []
    var localDNS = LocalDNS()
    let onCancel: () -> Void
    let onConfirm: (String, String?, [String]) -> Void

    @State private var name = ""
    @State private var site = ""
    @State private var dns: [String] = []

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var chosenSite: String? {
        currentSite == nil ? nil : XrayRealityService.normalisedSite(site)
    }

    private var canAdd: Bool {
        !trimmed.isEmpty && (currentSite == nil || chosenSite != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Device name", text: $name)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                } header: {
                    InfoSectionHeader("Name", note: "A name for you to recognise it by — “iPhone”, “work laptop”. The server may shorten it (an OpenVPN name becomes part of a certificate), and the list will show what it settled on.")
                }
                if currentSite != nil {
                    RealitySiteSection(site: $site)
                }
                Section {
                    VPNDNSMenu(title: "DNS", addresses: dns, local: localDNS) { dns = $0 }
                } footer: {
                    VPNDNSFootnote(protocolID: protocolID, resolverGone: localDNS.isGone(dns))
                }
            }
            .onAppear {
                if site.isEmpty { site = currentSite ?? "" }
                if dns.isEmpty { dns = defaultDNS }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 420, minHeight: 260)
            #endif
            .navigationTitle("New device")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onConfirm(trimmed, chosenSite, dns) }
                        .disabled(!canAdd)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

struct VPNClientConfigSheet: View {
    let device: VPNClientDevice
    let configuration: VPNClientConfiguration
    /// Which server issued this device, and under which protocol
    let serverID: UUID
    let serverName: String
    let protocolID: ServiceID
    var localDNS = LocalDNS()
    var onChangeDNS: (([String]) -> Void)?
    let onClose: () -> Void

    @ObservedObject private var tunnel = TunnelController.shared
    @State private var sharing = false
    @State private var fileURL: URL?
    @State private var copied = false
    @State private var adoptionError: String?
    @State private var handoffNote: LocalizedStringKey?

    var body: some View {
        NavigationStack {
            CardList {
                thisDeviceSection

                if configuration.qrIsUseful, let qr = VPNConfigQR.image(from: configuration.text) {
                    Section {
                        qr
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 260)
                            .padding(.vertical, 4)
                    } footer: {
                        Text("Scan this with the phone that will use the connection, from the protocol's own app.")
                    }
                }

                if let onChangeDNS {
                    Section {
                        VPNDNSMenu(title: "DNS", addresses: device.dns, local: localDNS, onChoose: onChangeDNS)
                    } footer: {
                        VPNDNSFootnote(protocolID: protocolID, changing: true, resolverGone: localDNS.isGone(device.dns))
                    }
                }

                Section {
                    Button {
                        copy(configuration.text)
                    } label: {
                        Label(copied ? "Copied" : "Copy configuration",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .rowActionButtonStyle()
                    Button {
                        share()
                    } label: {
                        Label("Share file…", systemImage: "square.and.arrow.up")
                    }
                    .rowActionButtonStyle()
                } footer: {
                    Text(verbatim: configuration.fileName)
                }

                Section {
                    Text(verbatim: configuration.text)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text("Configuration")
                } footer: {
                    Text("This contains the device's keys. Anyone holding it can connect as this device — hand it over the way you would a password, and remove the device here if it leaks.")
                }
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 560)
            #endif
            .navigationTitle(Text(verbatim: device.name))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
            .shareSheet(isPresented: $sharing, items: fileURL.map { [$0] } ?? [])
        }
    }

    // MARK: - This device

    @ViewBuilder
    private var thisDeviceSection: some View {
        let offers = DeviceConfigurationOffers.offers(protocolID: protocolID,
                                                      text: configuration.text,
                                                      platform: .current)
        if !offers.isEmpty {
            Section {
                if offers.keepsHere { useHereButton }
                handoffButton(offers.handoff)
                if let adoptionError {
                    Label(adoptionError, systemImage: HealthLevel.critical.systemImageName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let handoffNote {
                    Text(handoffNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("This device")
            } footer: {
                thisDeviceFooter(keepsHere: offers.keepsHere)
            }
        }
    }

    private var isAdopted: Bool {
        tunnel.hasProfile(serverID: serverID, protocolID: protocolID, deviceID: device.id)
    }

    @ViewBuilder
    private var useHereButton: some View {
        Button {
            adopt()
        } label: {
            Label(isAdopted ? "Kept on this device" : "Use on this device",
                  systemImage: isAdopted ? "checkmark" : "iphone.and.arrow.forward")
        }
        .rowActionButtonStyle()
    }

    @ViewBuilder
    private func handoffButton(_ handoff: ConfigurationHandoff) -> some View {
        switch handoff {
        case .configurationProfile:
            Button {
                installProfile()
            } label: {
                Label("Install as a system profile…", systemImage: "gear.badge")
            }
            .rowActionButtonStyle()
        case .openIn(let url):
            Button {
                open(url)
            } label: {
                Label("Open in the protocol's app…", systemImage: "arrow.up.forward.app")
            }
            .rowActionButtonStyle()
        case .fileOnly:
            EmptyView()
        }
    }

    @ViewBuilder
    private func thisDeviceFooter(keepsHere: Bool) -> some View {
        if keepsHere {
            if TunnelAvailability.kind == .simulated {
                Text("Kept here, this connection is a demonstration: it walks through connecting and counts traffic, but carries none. Install it as a system profile to actually connect.")
            } else {
                Text("Kept here, this connection is brought up by gryonixNexus itself and appears on the Connection card.")
            }
        } else if let refusal = VPNText.refusal(for: protocolID) {
            Text(verbatim: refusal)
        }
    }

    private func adopt() {
        adoptionError = nil
        do {
            let profile = try tunnel.adopt(configurationText: configuration.text,
                                           protocolID: protocolID,
                                           serverID: serverID,
                                           serverName: serverName,
                                           deviceID: device.id,
                                           deviceName: device.name)
            Task { await tunnel.choose(profile) }
        } catch {
            adoptionError = VPNText.message(for: error)
        }
    }

    private func installProfile() {
        handoffNote = nil
        Task {
            do {
                let data = try profileData()
                let step = try await ProfileInstaller.install(data, fileName: profileFileName)
                handoffNote = step == .openSettings
                    ? "Finish installing it in Settings › General › VPN & Device Management."
                    : "Confirm the install in the prompt that just opened."
            } catch {
                adoptionError = VPNText.message(for: error)
            }
        }
    }

    private func profileData() throws -> Data {
        let identifier = "\(serverID.uuidString).\(protocolID.rawValue).\(device.id)"
        if protocolID == .openVPN {
            return try VPNConfigurationProfile.plist(for: OpenVPNProfileConfig(parsing: configuration.text),
                                                     deviceName: device.name,
                                                     identifier: identifier,
                                                     platform: .current)
        }
        return try VPNConfigurationProfile.plist(for: WireGuardQuickConfig(parsing: configuration.text),
                                                 protocolID: protocolID,
                                                 deviceName: device.name,
                                                 identifier: identifier,
                                                 platform: .current)
    }

    private var profileFileName: String {
        DeviceConfigurationOffers.profileFileName(from: configuration.fileName,
                                                   deviceName: device.name)
    }

    private func open(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    private func share() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(configuration.fileName)
        do {
            try configuration.text.write(to: url, atomically: true, encoding: .utf8)
            fileURL = url
            sharing = true
        } catch {
            fileURL = nil
        }
    }

    private func copy(_ value: String) {
        SecretPasteboard.copy(value)
        copied = true
    }
}

/// The configuration as a QR code
enum VPNConfigQR {
    static func image(from text: String) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        #if os(iOS)
        return Image(uiImage: UIImage(cgImage: cgImage))
        #else
        return Image(nsImage: NSImage(cgImage: cgImage,
                                      size: NSSize(width: scaled.extent.width,
                                                   height: scaled.extent.height)))
        #endif
    }
}
