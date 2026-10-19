import AgentClient
import AgentControl
import ServerControl
import SwiftUI

@available(macOS 15.0, *)
struct DeviceManagementSheet: View {
    let deployment: Deployment

    @StateObject private var model = DeviceManagementModel()
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRevoke: Gryonixnexusd_V1_Device?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Paired Devices")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 380)
        #endif
        .task { await model.load(deployment: deployment) }
        .onDisappear { model.stop() }
        .alert("Remove this device?",
               isPresented: Binding(get: { confirmingRevoke != nil },
                                    set: { if !$0 { confirmingRevoke = nil } }),
               presenting: confirmingRevoke) { device in
            Button("Remove", role: .destructive) {
                Task { await model.revoke(device) }
                confirmingRevoke = nil
            }
            .dangerTint()
            Button("Cancel", role: .cancel) { confirmingRevoke = nil }
        } message: { device in
            Text(revokeMessage(device))
        }
        .alert("Could not remove the device",
               isPresented: Binding(get: { model.revokeError != nil },
                                    set: { if !$0 { model.revokeError = nil } })) {
            Button("OK") { model.revokeError = nil }
        } message: {
            Text(model.revokeError ?? "")
        }
    }

    private func revokeMessage(_ device: Gryonixnexusd_V1_Device) -> String {
        let name = device.label.isEmpty ? UIL10n.string("This device") : device.label
        return UIL10n.string(
            "%@ is removed from the server's paired-device list. This does NOT revoke its SSH access — its key keeps working until it is removed from the server separately.",
            name)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            VStack {
                Spacer(minLength: 0)
                ProgressView()
                Spacer(minLength: 0)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label(model.needsSignIn ? "This device is signed out" : "Could not load devices",
                      systemImage: model.needsSignIn ? "lock.trianglebadge.exclamationmark"
                                                     : "exclamationmark.triangle")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if model.needsSignIn {
                    Button {
                        Task { await model.signInAgain(deployment: deployment) }
                    } label: {
                        if model.signingIn {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Signing in…") }
                        } else {
                            Text("Sign in again")
                        }
                    }
                    .prominentActionButtonStyle()
                    .disabled(model.signingIn)
                }
            }
            .padding()
        case .loaded(let devices):
            CardList {
                autoLogoutSection
                Section {
                    if devices.isEmpty {
                        Text("No devices are registered with this server's agent yet.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(devices, id: \.id) { device in
                            row(device)
                        }
                    }
                    if let enrolmentNote = model.enrolmentNote {
                        Label(enrolmentNote, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    InfoSectionHeader("Paired devices") {
                        Text("This device is added to the list the first time it opens this screen. Removing one only forgets it — it does not revoke its SSH access.")
                        Text("Devices are told apart by the server key. A server moved to another device with Export carries that key, so both show as the same entry — adopt the server on the other device instead to have it listed separately.")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var autoLogoutSection: some View {
        Section {
            WrappingPicker("Sign out devices after", selection: Binding(
                get: { model.autoLogoutMonths },
                set: { model.setAutoLogout(months: $0, deployment: deployment) }
            )) {
                Text("Never").tag(Int32(0))
                Text("1 month").tag(Int32(1))
                Text("3 months").tag(Int32(3))
                Text("6 months").tag(Int32(6))
                Text("1 year").tag(Int32(12))
            }
            .disabled(model.savingPolicy)
            if let error = model.policyError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            InfoSectionHeader("Sign out devices after") {
                Text("A device past its date has to sign in again — Face ID on the device, and a fresh pairing code from this server. Its saved passwords are cleared until it does.")
                Text("This does NOT revoke SSH access — a device's key keeps working until it is removed from the server separately.")
            }
        } footer: {
            if model.autoLogoutMonths != 0 {
                Text("Devices running an older version of the app cannot sign in while this is on — update them first.")
            }
        }
    }

    @ViewBuilder
    private func row(_ device: Gryonixnexusd_V1_Device) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: device))
                .foregroundStyle(model.isThisDevice(device) ? Color.green : Color.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if device.label.isEmpty {
                        Text("Unnamed device")
                    } else {
                        Text(verbatim: device.label)
                    }
                    if model.isThisDevice(device) {
                        Text("This device")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(pairedAtText(device.pairedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if device.expiresAt > 0 {
                    Text(expiryText(device.expiresAt))
                        .font(.caption)
                        .foregroundStyle(isExpired(device) ? Color.orange : Color.secondary)
                }
                if device.lastSeenAt > 0 {
                    Text(lastSeenText(device.lastSeenAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.revoking == device.id {
                ProgressView().controlSize(.small)
            } else {
                Button(role: .destructive) {
                    confirmingRevoke = device
                } label: {
                    Image(systemName: "trash")
                }
                .dangerTint()
                .glassIconButtonStyle()
            }
        }
    }

    /// This device is known outright; the rest by their label
    private func icon(for device: Gryonixnexusd_V1_Device) -> String {
        let symbol = PairedDeviceIcon.symbol(for: device.label)
        guard symbol == PairedDeviceIcon.unknown, model.isThisDevice(device) else { return symbol }
        return PairedDeviceIcon.thisDevice
    }

    private func pairedAtText(_ millis: Int64) -> String {
        guard millis > 0 else { return UIL10n.string("Paired date unknown") }
        let date = Date(timeIntervalSince1970: Double(millis) / 1000)
        return UIL10n.string("Paired %@", date.formatted(date: .abbreviated, time: .shortened))
    }

    private func expiryText(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(millis) / 1000)
        let formatted = date.formatted(date: .abbreviated, time: .shortened)
        return date <= Date()
            ? UIL10n.string("Signed out %@", formatted)
            : UIL10n.string("Signs out %@", formatted)
    }

    private func lastSeenText(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(millis) / 1000)
        return UIL10n.string("Last seen %@", date.formatted(date: .abbreviated, time: .shortened))
    }

    private func isExpired(_ device: Gryonixnexusd_V1_Device) -> Bool {
        device.expiresAt > 0 && Date(timeIntervalSince1970: Double(device.expiresAt) / 1000) <= Date()
    }
}

@available(macOS 15.0, *)
@MainActor
final class DeviceManagementModel: ObservableObject {
    enum State {
        case loading
        case failed(String)
        case loaded([Gryonixnexusd_V1_Device])
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var revoking: String?
    @Published var revokeError: String?
    /// 0 (never), 1, 3, 6 or 12
    @Published private(set) var autoLogoutMonths: Int32 = 0
    @Published private(set) var savingPolicy = false
    @Published private(set) var policyError: String?
    @Published private(set) var needsSignIn = false
    @Published private(set) var signingIn = false
    @Published fileprivate(set) var enrolmentNote: String?

    private var session: AgentConnection.Session?
    private var thisDeviceUID: String = ""
    private var thisDevicePublicKey: String?

    func load(deployment: Deployment) async {
        thisDeviceUID = await Task.detached(priority: .userInitiated) { DeviceIdentity.uid }.value
        do {
            let opened = try await AgentConnection.open(deployment: deployment)
            thisDevicePublicKey = await AgentDeviceEnrolment.publicKey(for: deployment)
            session = opened
            let listed = try await AgentDeviceOperations(client: opened.client).listDevices()
            let devices = await AgentDeviceEnrolment.ensureRegistered(
                session: opened, deployment: deployment, devices: listed,
                thisDevicePublicKey: thisDevicePublicKey) { [weak self] message in
                    self?.enrolmentNote = message
                }
            state = .loaded(devices.uniquedByID().sorted { $0.pairedAt < $1.pairedAt })
            autoLogoutMonths = (try? await AgentDeviceOperations(client: opened.client)
                .sessionPolicy().autoLogoutMonths) ?? 0
        } catch {
            needsSignIn = AccessVault.isSessionExpired(error)
            let message: String
            if needsSignIn {
                message = UIL10n.string("This server signs devices out on a schedule, and this device's turn has come. Signing in again needs Face ID or your passcode.")
            } else if AccessVault.isUnidentified(error) {
                message = UIL10n.string("This device cannot tell the server which device it is, so the server refuses every request. This is not the session timer, and signing in again will not help.")
            } else {
                message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            state = .failed(message)
        }
    }

    func signInAgain(deployment: Deployment) async {
        guard !signingIn else { return }
        signingIn = true
        defer { signingIn = false }
        guard await BiometricGate.authenticate(
            reason: UIL10n.string("Unlock to sign this device in to the server")) else { return }
        do {
            let opened = try await AgentConnection.open(deployment: deployment)
            let previous = session?.runner
            session = opened
            if let previous { Task { await previous.disconnect() } }
            _ = try await AgentDeviceEnrolment.enrol(session: opened, deployment: deployment)
            needsSignIn = false
            state = .loading
            await load(deployment: deployment)
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func revoke(_ device: Gryonixnexusd_V1_Device) async {
        guard let session, case .loaded(let devices) = state else { return }
        revoking = device.id
        defer { revoking = nil }
        do {
            try await AgentDeviceOperations(client: session.client).revoke(deviceID: device.id)
            state = .loaded(devices.filter { $0.id != device.id })
        } catch {
            revokeError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func isThisDevice(_ device: Gryonixnexusd_V1_Device) -> Bool {
        if !thisDeviceUID.isEmpty, !device.deviceUid.isEmpty {
            return device.deviceUid == thisDeviceUID
        }
        guard let thisDevicePublicKey, !thisDevicePublicKey.isEmpty else { return false }
        return device.publicKey == thisDevicePublicKey
    }

    func setAutoLogout(months: Int32, deployment: Deployment) {
        guard let session else { return }
        let previous = autoLogoutMonths
        autoLogoutMonths = months
        savingPolicy = true
        policyError = nil
        Task { @MainActor in
            defer { savingPolicy = false }
            do {
                let operations = AgentDeviceOperations(client: session.client)
                let policy = try await operations.setSessionPolicy(months: months)
                autoLogoutMonths = policy.autoLogoutMonths
                let devices = try await operations.listDevices()
                state = .loaded(devices.uniquedByID().sorted { $0.pairedAt < $1.pairedAt })
            } catch {
                autoLogoutMonths = previous
                policyError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func stop() {
        let runner = session?.runner
        session = nil
        guard let runner else { return }
        Task { await runner.disconnect() }
    }
}

@available(macOS 15.0, *)
extension Array where Element == Gryonixnexusd_V1_Device {
    func uniquedByID() -> [Element] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}
