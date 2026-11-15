import AgentClient
import SwiftUI

/// What decides the tunnels' speed on this server
struct VPNSpeedView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var facts: Loadable<Gryonixnexusd_V1_VpnSpeedFacts> = .idle
    /// UDP drops when the screen opened, to count from
    @State private var firstDrops: UInt64?
    @State private var switching = false

    var body: some View {
        Form {
            if let facts = facts.value {
                tunnels(facts)
                AmneziaKernelSection(facts: facts, switching: switching, set: setKernel)
                server(facts)
            } else if let message = facts.errorMessage {
                Section { Text(verbatim: message).foregroundStyle(.secondary) }
            } else {
                Section { ProgressView() }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .screenTitle("Tunnel speed")
        .refreshableWithShortcut { await load() }
        .task { await followWhileWorking() }
    }

    private static func drops(_ facts: Gryonixnexusd_V1_VpnSpeedFacts) -> UInt64 {
        facts.udpReceiveErrors + facts.udpBufferErrors
    }

    private func show(_ fresh: Gryonixnexusd_V1_VpnSpeedFacts) {
        if firstDrops == nil { firstDrops = Self.drops(fresh) }
        facts = .loaded(fresh)
    }

    private func load() async {
        do {
            show(try await viewModel.vpnSpeedFacts())
        } catch {
            facts = .failed(DashboardViewModel.message(for: error))
        }
    }

    /// Reads again while the module is being switched
    private func followWhileWorking() async {
        await load()
        while facts.value?.amneziaKernelStatus == "working", !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            await load()
        }
    }

    private func setKernel(_ enabled: Bool) {
        switching = true
        Task {
            defer { switching = false }
            do {
                show(try await viewModel.setAmneziaKernel(enabled))
            } catch {
                facts = .failed(DashboardViewModel.message(for: error))
            }
            await followWhileWorking()
        }
    }

    private func tunnels(_ facts: Gryonixnexusd_V1_VpnSpeedFacts) -> some View {
        Section {
            ForEach(facts.interfaces, id: \.interface) { tunnel in
                LabeledContent {
                    Text(verbatim: "MTU \(tunnel.mtu)")
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: tunnel.protocol == "amneziawg" ? "AmneziaWG" : "WireGuard")
                        Text(tunnel.kernel ? "In the kernel" : "As a program, slower than the kernel")
                            .font(.caption)
                            .foregroundStyle(tunnel.kernel ? Color.secondary : Color.orange)
                    }
                }
            }
        } header: {
            InfoSectionHeader("Tunnels", note: "A server MTU larger than the phones' sends packets the way cannot carry, so they are split or lost. The agent sets it to the phones' value within ten minutes.")
        } footer: {
            if facts.interfaces.contains(where: { !$0.kernel }) {
                Text("A tunnel that runs as a program is limited by the server's processor. In the kernel it is as fast as WireGuard.")
            }
        }
    }

    private func server(_ facts: Gryonixnexusd_V1_VpnSpeedFacts) -> some View {
        Section {
            LabeledContent("Processor cores") { Text(verbatim: "\(facts.cpuCores)") }
            LabeledContent("Load") {
                Text(verbatim: String(format: "%.2f", facts.load))
                    .foregroundStyle(facts.load >= Double(max(facts.cpuCores, 1)) ? .orange : .secondary)
            }
            LabeledContent("UDP packets dropped") { Text(verbatim: "\(Self.drops(facts))") }
            LabeledContent("Since this screen opened") {
                Text(verbatim: "+\(Self.drops(facts) - min(firstDrops ?? Self.drops(facts), Self.drops(facts)))")
            }
        } header: {
            Text("Server")
        } footer: {
            Text("Run a speed test, then pull to read again: drops that grow during the test cost speed.")
        }
    }
}

/// The switch that moves AmneziaWG into the kernel
struct AmneziaKernelSection: View {
    let facts: Gryonixnexusd_V1_VpnSpeedFacts
    let switching: Bool
    let set: (Bool) -> Void

    private var status: String { facts.amneziaKernelStatus }
    private var hasAmnezia: Bool { facts.interfaces.contains { $0.protocol == "amneziawg" } }

    var body: some View {
        if hasAmnezia || status == "on" || status == "working" {
            Section {
                Toggle(isOn: Binding(get: { status == "on" || status == "working" }, set: set)) {
                    Text("AmneziaWG in the kernel")
                }
                .disabled(switching || status == "working" || (!facts.amneziaKernelPossible && status != "on"))
                if status == "working" {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Building the module on the server, a few minutes. AmneziaWG keeps working.")
                            if let step = Self.step(facts.amneziaKernelNote) {
                                Text("Step \(step.done) of \(step.all)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                footer
            }
        }
    }

    /// How far the agent got, from a note like "3/4"
    static func step(_ note: String) -> (done: Int, all: Int)? {
        let parts = note.split(separator: "/")
        guard parts.count == 2, let done = Int(parts[0]), let all = Int(parts[1]), done > 0, done <= all else { return nil }
        return (done, all)
    }

    @ViewBuilder private var footer: some View {
        if status == "failed", !facts.amneziaKernelNote.isEmpty {
            Text("It did not work, so AmneziaWG stays a program: \(facts.amneziaKernelNote)")
        } else if !facts.amneziaKernelPossible, status != "on" {
            Text("Needs a Debian or Ubuntu server with 1 GB free on the disk.")
        } else {
            Text("In the kernel AmneziaWG uses far less of the processor. It takes about 300–400 MB of disk for the kernel headers and compiler; switch it off to free them.")
        }
    }
}
