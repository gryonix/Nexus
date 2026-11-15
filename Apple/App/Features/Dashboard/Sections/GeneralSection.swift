import ServerControl
import SwiftUI

/// How the server is reached: routing, its machines, its DNS
struct GeneralStatusSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onUpdate: (Deployment) -> Void
    let onDynamicDNS: () -> Void

    var body: some View {
        Section {
            if viewModel.isRelay { relayRows }
            NavigationLink {
                DeploymentNodesView(deployment: viewModel.deployment, onUpdate: onUpdate)
            } label: {
                Label("Servers", systemImage: "server.rack")
            }
            #if os(tvOS)
            if viewModel.canManageDynamicDNS, let state = viewModel.dynamicDNS {
                LabeledContent {
                    Text(state.enabled ? "On" : "Off")
                } label: {
                    Label("Dynamic DNS", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            #else
            if viewModel.canManageDynamicDNS {
                Button(action: onDynamicDNS) {
                    HStack {
                        Label("Dynamic DNS", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if let state = viewModel.dynamicDNS {
                            Text(state.enabled ? "On" : "Off").foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .infoNote("Dynamic DNS", "On a connection whose address changes, the server updates its own DNS records on a timer — it keeps working while this app is closed.")
            }
            #endif
        } header: {
            Text("Connection")
        }
    }

    @ViewBuilder private var relayRows: some View {
        StatusRow(title: "Traffic routing",
                  state: viewModel.forwarding,
                  health: { $0 ? .ok : .critical },
                  text: { UIL10n.string($0 ? "on" : "off") })
        if viewModel.canProvisionRelay {
            Button {
                Task { await viewModel.provisionRelay() }
            } label: {
                Label("Configure the relay", systemImage: "arrow.left.arrow.right")
            }
            .infoNote("Configure the relay", "The relay forwards this deployment's ports into the tunnel. Configure it after installing or removing services, so its firewall matches what the local server now runs.")
        }
        if viewModel.onFallbackAddress {
            Label("Reached through the fallback address", systemImage: "arrow.triangle.branch")
                .foregroundStyle(.orange)
                .font(.callout)
        }
        StatusRow(title: "Server online",
                  state: viewModel.vpsPing,
                  health: { $0.isAlive ? .ok : .critical },
                  text: { UIL10n.string($0.isAlive ? "responding" : "not responding") })
        StatusRow(title: "Local server link",
                  state: viewModel.tunnelPing,
                  health: { $0.isAlive ? .ok : .critical },
                  text: { UIL10n.string($0.isAlive ? "responding" : "not responding") })
    }
}

struct HostControlSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onRepair: () -> Void
    let onReinstall: () -> Void
    let onUpdate: (Deployment) -> Void
    @State private var confirmingWireGuardRestart = false
    @State private var confirmingSSHRestart = false
    @State private var confirmingFullRestart = false
    @State private var rebootTarget: SSHHostID?
    @State private var confirmingPowerOff = false

    var body: some View {
        Section("Actions") {
            machineAlerts(restartAlerts(
                CompactActionGroup(serviceActions + machineActions + repairActions)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 2)
            ))
        }
    }

    private var serviceActions: [CompactAction] {
        [
            CompactAction("Restart WireGuard", systemImage: "arrow.clockwise") {
                confirmingWireGuardRestart = true
            },
            CompactAction("Restart SSH", systemImage: "arrow.clockwise") {
                confirmingSSHRestart = true
            }
        ]
    }

    private var machineActions: [CompactAction] {
        viewModel.deployment.nodes.map { node in
            CompactAction(LocalizedStringKey(DashboardViewModel.rebootTitle(for: node, in: viewModel.deployment)),
                          systemImage: "power", role: .destructive) {
                rebootTarget = node.sshHost
            }
        } + (WakeOnLANAvailability.isOffered(for: viewModel.deployment) ? powerActions : [])
    }

    private var powerActions: [CompactAction] {
        [
            CompactAction("Shut down", systemImage: "power.dotted", role: .destructive) {
                confirmingPowerOff = true
            },
            CompactAction("Wake on LAN", systemImage: "bolt") {
                Task { if let updated = await viewModel.wakeUp() { onUpdate(updated) } }
            }
        ]
    }

    private var repairActions: [CompactAction] {
        [
            CompactAction("Repair server", systemImage: "wrench.and.screwdriver") { onRepair() },
            CompactAction("Reinstall services", systemImage: "arrow.triangle.2.circlepath") { onReinstall() },
            CompactAction("Restart everything", systemImage: "arrow.triangle.2.circlepath") {
                confirmingFullRestart = true
            }
        ]
    }

    private func restartAlerts(_ content: some View) -> some View {
        content
            .alert("Restart WireGuard on the VPS and the local server?",
                   isPresented: $confirmingWireGuardRestart) {
                Button("Restart", role: .destructive) {
                    Task { await viewModel.restartWireGuardBoth() }
                }
                .dangerTint()
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The tunnel will drop briefly. Recovery is checked by pinging from the VPS for up to 60 seconds.")
            }
            .alert("Restart everything?",
                   isPresented: $confirmingFullRestart) {
                Button("Restart", role: .destructive) {
                    Task { await viewModel.restartEverything() }
                }
                .dangerTint()
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Restarts the services on the local server, then the tunnel on both machines, and waits for it to come back. Each step is shown as it happens.")
            }
            .alert(viewModel.sshdRestartQuestion,
                   isPresented: $confirmingSSHRestart) {
                Button("Restart", role: .destructive) {
                    Task { await viewModel.restartSSHDEverywhere() }
                }
                .dangerTint()
                Button("Cancel", role: .cancel) {}
            }
    }

    private func machineAlerts(_ content: some View) -> some View {
        content
            .alert("Reboot this machine?",
                   isPresented: Binding(get: { rebootTarget != nil },
                                        set: { if !$0 { rebootTarget = nil } })) {
                Button("Reboot", role: .destructive) {
                    if let target = rebootTarget {
                        Task { await viewModel.rebootHost(target) }
                    }
                    rebootTarget = nil
                }
                .dangerTint()
                Button("Cancel", role: .cancel) { rebootTarget = nil }
            } message: {
                Text("The machine will go offline for about a minute while it restarts.")
            }
            .alert("Shut down this machine?", isPresented: $confirmingPowerOff) {
                Button("Shut down", role: .destructive) {
                    Task { await viewModel.powerOffWakeTarget() }
                }
                .dangerTint()
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It stays off until Wake on LAN or its power button turns it on.")
            }
    }
}
