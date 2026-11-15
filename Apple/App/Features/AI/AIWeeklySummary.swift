import AIAssistant
import ServerControl
import SwiftUI

@MainActor
enum AIWeeklySummary {
    static func context() async -> AIContext {
        let deployments = (try? FileDeploymentStore().load()) ?? []
        var lines: [String] = []
        for deployment in deployments where !DemoServer.isBuiltIn(deployment) {
            lines.append(await digest(deployment))
        }
        let events = IslandJournal.shared.entries
            .filter { $0.at > Date().addingTimeInterval(-7 * 86_400) }
            .suffix(60).map { IslandJournal.line($0) }
        return AIContext(kind: .weekly, title: "Weekly summary",
                         sections: [("Metrics, last 7 days", lines.joined(separator: "\n")),
                                    ("Recent events", events.joined(separator: "\n"))])
    }

    private static func digest(_ deployment: Deployment) async -> String {
        let model = MetricsHistoryViewModel(deployment: deployment, host: deployment.servicesHost)
        model.range = .week
        await model.load()
        defer { model.teardown() }
        let samples = model.points.map { point in
            AIUsageSample(
                time: point.date, cpuPercent: point.cpuPercent,
                memoryFraction: point.memTotalBytes > 0 ? Double(point.memUsedBytes) / Double(point.memTotalBytes) : nil,
                diskFraction: point.diskTotalBytes > 0 ? Double(point.diskUsedBytes) / Double(point.diskTotalBytes) : nil,
                temperature: point.temperatureCelsius)
        }
        return AIWeeklyDigest.lines(server: deployment.name, samples: samples)
    }
}
