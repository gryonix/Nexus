import Foundation
import SwiftUI
import VPNTunnel

/// What the "Server status" intent says about one server
struct ServerStatusReport: Equatable {
    enum State: Equatable { case online, offline, unknown }

    let name: String
    let state: State
    let cpu: Double?
    let memory: Double?
    let disk: Double?
    let problems: Int

    init(name: String, server: FleetSnapshot.Server?) {
        self.name = name
        guard let server else {
            state = .unknown; cpu = nil; memory = nil; disk = nil; problems = 0
            return
        }
        if server.failure != nil {
            state = .offline
        } else {
            state = server.metrics != nil || server.services != nil ? .online : .unknown
        }
        cpu = server.metrics?.cpuPercent
        memory = server.metrics?.memoryPercent
        disk = server.metrics?.diskPercent
        problems = server.services?.needingAttention ?? 0
    }

    var sentence: String {
        switch state {
        case .unknown: return UIL10n.string("No reading for %@ yet.", name)
        case .offline: return UIL10n.string("%@ is offline.", name)
        case .online:
            let load = UIL10n.string("CPU %@, memory %@, disk %@.",
                                     ServerMetricsPresentation.percent(cpu),
                                     ServerMetricsPresentation.percent(memory),
                                     ServerMetricsPresentation.percent(disk))
            let verdict = problems == 0
                ? UIL10n.string("No problems.")
                : UIL10n.string("Problems: %lld.", problems)
            return UIL10n.string("%@ is online.", name) + " " + load + " " + verdict
        }
    }
}

struct ServerStatusSnippet: View {
    let report: ServerStatusReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.name).font(.headline)
            Text(report.sentence).font(.subheadline).foregroundStyle(.secondary)
            if report.state == .online {
                bar("CPU", report.cpu)
                bar("RAM", report.memory)
                bar("Disk", report.disk)
            }
        }
        .padding()
    }

    private func bar(_ title: String, _ percent: Double?) -> some View {
        HStack {
            Text(verbatim: title).font(.caption).frame(width: 40, alignment: .leading)
            ProgressView(value: min(max((percent ?? 0) / 100, 0), 1))
                .tint(ServerMetricsPresentation.tint(percent))
        }
    }
}
