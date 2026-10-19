import SwiftUI
import gryonixNexusCore

/// Typing an activation code, or showing the one in use.
struct LicenseCodeSection: View {
    @ObservedObject private var license = LicenseStore.shared
    @State private var input = ""
    @State private var isWorking = false
    @State private var failure: String?

    var body: some View {
        Section {
            if let code = license.code, license.status.isActive {
                CopyableCode(code: code)
                Button("Remove from this device", role: .destructive) {
                    Task { await license.removeFromThisDevice() }
                }
                .dangerTint()
            } else {
                entry
            }
        } header: {
            Text("Activation code")
        } footer: {
            Text("The code of your purchase, shown on another of your devices.")
        }
    }

    @ViewBuilder
    private var entry: some View {
        TextField(text: $input, prompt: Text(verbatim: "XXXXX-XXXXX-XXXXX-XXXXX")) {
            Text("Activation code")
        }
        .labelsHidden()
        .font(.body.monospaced())
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.characters)
        #endif
        Button("Activate") { Task { await activate() } }
            .disabled(isWorking || ActivationCode.normalize(input) == nil)
        if let failure { Text(failure).font(.footnote).foregroundStyle(.red) }
    }

    private func activate() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await license.activate(code: input)
            input = ""
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// Devices using this code, each removable.
struct LicenseDevicesSection: View {
    @ObservedObject private var license = LicenseStore.shared
    @State private var list: LicenseAPI.DeviceList?
    @State private var failure: String?

    var body: some View {
        Section {
            ForEach(list?.devices ?? []) { device in
                DeviceRow(device: device, isThis: device.device == DeviceIdentity.uid) {
                    Task { await remove(device) }
                }
            }
            if let failure { Text(failure).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("Devices")
        } footer: {
            if let list { Text("\(list.devices.count) of \(list.limit)") }
        }
        .task(id: license.code) { await load() }
    }

    private func load() async {
        guard let code = license.code else { return }
        do {
            list = try await LicenseAPI.devices(code: code)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    private func remove(_ device: LicenseAPI.Device) async {
        guard let code = license.code else { return }
        try? await LicenseAPI.deactivate(code: code, device: device.device)
        await load()
    }
}

private struct DeviceRow: View {
    let device: LicenseAPI.Device
    let isThis: Bool
    let remove: () -> Void

    var body: some View {
        HStack {
            Label(device.name ?? device.platform ?? "—", systemImage: icon)
            if isThis { Text("This device").font(.footnote).foregroundStyle(.secondary) }
            Spacer()
            if !isThis {
                Button(role: .destructive, action: remove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .dangerTint()
                .accessibilityLabel(Text("Remove"))
            }
        }
    }

    private var icon: String {
        switch device.platform {
        case "macos": return "laptopcomputer"
        case "android": return "candybarphone"
        default: return "iphone"
        }
    }
}
