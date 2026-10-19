import ServerControl
import SwiftUI

struct GeneralStatusSection: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        Section("Connection") {
            StatusRow(title: "Traffic routing",
                      state: viewModel.forwarding,
                      health: { $0 ? .ok : .critical },
                      text: { UIL10n.string($0 ? "on" : "off") })
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
