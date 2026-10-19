import SwiftUI
import gryonixNexusCore
import ServiceCatalog

struct ServiceAdvancedFields: View {
    @ObservedObject var viewModel: ServiceConfigViewModel
    let id: ServiceID

    /// Whether this service puts anything under the disclosure at all
    static func hasFields(for id: ServiceID) -> Bool {
        if ServiceSettings.hostnameSettings[id] != nil { return true }
        switch id {
        case .mailcow, .mailu, .dockerMailserver, .vaultwarden, .forgejo,
             .authelia, .pihole, .minecraftJava, .minecraftBedrock, .gitlab,
             .homeAssistant:
            return true
        default:
            return false
        }
    }

    var body: some View {
        if ServiceSettings.hostnameSettings[id] != nil {
            TechnicalField(title: "\(viewModel.serviceDisplayName(id)) domain",
                           prompt: viewModel.serviceHostnamePlaceholder(id),
                           text: viewModel.hostnameBinding(id), ownAddress: true)
        }
        switch id {
        case .mailcow, .mailu, .dockerMailserver:
            LabeledContent("Mail domain", value: viewModel.hostnamePlaceholder)
                .foregroundStyle(.secondary)
        case .vaultwarden:
            Toggle("Open registration", isOn: $viewModel.vaultwardenAllowSignups)
        case .forgejo:
            TechnicalField(title: "Git SSH port (0 — off)",
                           prompt: "2222",
                           text: $viewModel.forgejoSSHPort)
        case .authelia:
            autheliaFields
        case .pihole:
            Toggle("Serve DNS to the local network", isOn: $viewModel.piholeServesNetwork)
            Label(viewModel.piholeServesNetwork
                  ? "Port 53 is published on every interface. Only do this where it cannot be reached from the internet — an open resolver is abused for amplification attacks within days."
                  : "DNS answers on this machine only. Devices on your network cannot use the filter until you turn this on.",
                  systemImage: viewModel.piholeServesNetwork ? "exclamationmark.triangle" : "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .homeAssistant:
            homeAssistantFields
        case .minecraftJava:
            minecraftJavaFields
        case .minecraftBedrock:
            TechnicalField(title: "Game version (empty — latest)",
                           prompt: "1.21.44",
                           text: $viewModel.minecraftBedrockVersion)
            TechnicalField(title: "Port (UDP)",
                           prompt: "19132",
                           text: $viewModel.minecraftBedrockPort)
            Label("Mojang ships this server for x86 only. On an ARM machine it runs under emulation and is noticeably slower.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .gitlab:
            TechnicalField(title: "Git SSH port (0 — off)",
                           prompt: "2223",
                           text: $viewModel.gitlabSSHPort)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var homeAssistantFields: some View {
        TechnicalField(title: "Zigbee or Z-Wave stick (empty — none)",
                       prompt: "/dev/serial/by-id/usb-...",
                       text: $viewModel.homeAssistantUSBDevice)
        if viewModel.canListSerialDevices { serialPicker }
        Label("The path survives a reboot only under /dev/serial/by-id — a plain /dev/ttyUSB0 can point at a different stick after the next start.",
              systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// The sticks the server itself reports
    @ViewBuilder
    private var serialPicker: some View {
        switch viewModel.serialListing {
        case .idle:
            Button("Read the sticks off the server", systemImage: "arrow.down.circle") {
                Task { await viewModel.loadSerialDevices() }
            }
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Asking the server…").foregroundStyle(.secondary)
            }
        case .loaded(let devices, let directoryPresent):
            ForEach(devices) { device in
                Button { viewModel.homeAssistantUSBDevice = device.path } label: {
                    serialRow(device)
                }
                .buttonStyle(.plain)
            }
            if devices.isEmpty { emptyPickerNote(directoryPresent: directoryPresent) }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func serialRow(_ device: SerialDeviceOption) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.label)
                Text(device.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if viewModel.homeAssistantUSBDevice == device.path {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func emptyPickerNote(directoryPresent: Bool) -> some View {
        Label(directoryPresent
              ? "The server sees no stick plugged in. Plug it in and read the list again."
              : "This machine has never had a USB serial adapter — there is nothing to pick yet.",
              systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var autheliaFields: some View {
        if !viewModel.autheliaCandidates.isEmpty {
            Toggle(isOn: Binding(
                get: { viewModel.allAutheliaCandidatesProtected },
                set: { viewModel.setAllAutheliaProtection($0) }
            )) {
                Label("Put everything behind the login", systemImage: "lock.square.stack")
            }
        }
        ForEach(viewModel.autheliaCandidates, id: \.self) { candidate in
            Toggle(isOn: viewModel.autheliaProtectionBinding(candidate)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.serviceDisplayName(candidate))
                    if AutheliaService.breaksAppClients.contains(candidate) {
                        Text("Its phone app signs in with its own account and cannot pass this login — the app stops connecting, the website keeps working.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        if viewModel.autheliaCandidates.isEmpty {
            Label("Turn on the services you want behind one login — they will appear here.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var minecraftJavaFields: some View {
        WrappingPicker("Server type", selection: $viewModel.minecraftJavaFlavour) {
            Text(verbatim: "Paper").tag("PAPER")
            Text(verbatim: "Vanilla").tag("VANILLA")
            Text(verbatim: "Fabric").tag("FABRIC")
            Text(verbatim: "Forge").tag("FORGE")
        }
        TechnicalField(title: "Game version (empty — latest)",
                       prompt: "1.21.4",
                       text: $viewModel.minecraftJavaVersion)
        TechnicalField(title: "Memory, MB",
                       prompt: "2048",
                       text: $viewModel.minecraftJavaMemoryMB)
        TechnicalField(title: "Port",
                       prompt: "25565",
                       text: $viewModel.minecraftJavaPort)
        TechnicalField(title: "Whitelist (names, comma separated)",
                       prompt: "dana, alex",
                       text: $viewModel.minecraftJavaWhitelist)
        TechnicalField(title: "Operators (names, comma separated)",
                       prompt: "dana",
                       text: $viewModel.minecraftJavaOperators)
        if viewModel.minecraftJavaWhitelist.trimmingCharacters(in: .whitespaces).isEmpty {
            Label("With no whitelist, anyone who knows the address can join.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// One VPN protocol's own port fields
struct VPNProtocolAdvancedFields: View {
    @ObservedObject var viewModel: ServiceConfigViewModel
    let proto: ServiceID

    var body: some View {
        switch proto {
        case .wireguardVPN:
            TechnicalField(title: "VPN port (UDP)",
                           prompt: viewModel.topology == .vpsRelayWithHomeBackend ? "51821" : "51820",
                           text: $viewModel.wireguardVPNPort)
        case .amneziaWG:
            TechnicalField(title: "AmneziaWG port (UDP)",
                           prompt: "51822",
                           text: $viewModel.amneziaWGPort)
        case .shadowsocks:
            TechnicalField(title: "Shadowsocks port (TCP/UDP)",
                           prompt: "8388",
                           text: $viewModel.shadowsocksPort)
        case .xrayReality:
            TechnicalField(title: "Reality port (TCP)",
                           prompt: "8443",
                           text: $viewModel.xrayRealityPort)
            TechnicalField(title: "Camouflage site (SNI)",
                           prompt: "www.apple.com",
                           text: $viewModel.xrayRealitySNI)
        case .openVPN:
            TechnicalField(title: "OpenVPN port (UDP)",
                           prompt: "1194",
                           text: $viewModel.openVPNPort)
        default:
            EmptyView()
        }
    }
}
