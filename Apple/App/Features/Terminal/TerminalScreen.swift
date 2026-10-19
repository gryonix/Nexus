import ServerControl
import ServerControlSSH
import SwiftUI

/// A live shell, full screen
@available(macOS 15.0, *)
struct TerminalScreen: View {
    let deployment: Deployment
    let profile: TerminalProfile

    @ObservedObject private var controller: TerminalController
    @Environment(\.dismiss) private var dismiss

    init(deployment: Deployment, profile: TerminalProfile) {
        self.deployment = deployment
        self.profile = profile
        controller = TerminalSessions.shared.controller(for: profile, on: deployment)
    }

    var body: some View {
        ZStack {
            TerminalHostView(controller: controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            switch controller.state {
            case .connecting:
                banner {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Connecting…")
                    }
                }
            case .closed(let reason):
                banner {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(reason == nil ? "The session ended." : "The session was disconnected.")
                        if let reason {
                            Text(verbatim: reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Button("Reconnect") { Task { await start() } }
                            .secondaryActionButtonStyle()
                    }
                }
            case .idle, .live:
                EmptyView()
            }
        }
        .navigationTitle(Text(verbatim: "\(profile.username)@\(deployment.name)"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    TerminalSessions.shared.end(profile)
                    dismiss()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .tint(.red)
                .toolbarGlassButtonStyle()
            }
        }
        // The emulator and its keyboard accessory own the bottom edge.
        .ownsBottomEdge()
        .task {
            #if DEBUG
            if let canned = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_TERMINAL"] {
                controller.feedDebug(canned)
                return
            }
            #endif
            if controller.state == .idle { await start() }
        }
    }

    @ViewBuilder
    private func banner<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack {
            Spacer()
            content()
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding()
        }
    }

    private func start() async {
        let deployment = deployment
        let profile = profile
        let resolved: Result<(TerminalEndpointBuilder.Target, TerminalLogin), Error> =
            await Task.detached {
                do {
                    let target = try TerminalEndpointBuilder.target(for: deployment,
                                                                    nodeID: profile.nodeID)
                    let login = try TerminalEndpointBuilder.login(for: profile,
                                                                  deployment: deployment)
                    return .success((target, login))
                } catch {
                    return .failure(error)
                }
            }.value
        switch resolved {
        case .failure(let error):
            controller.reportFailure(error.localizedDescription)
        case .success(let (target, login)):
            let pins = HostKeyPinStore(deploymentID: deployment.id)
            let hosts = target.pinTargets
            await controller.connect(endpoint: target.endpoint, login: login,
                                     columns: 80, rows: 24) { host, key in
                guard let id = hosts[host] else { return }
                pins.store(key, for: id)
            }
        }
    }
}
