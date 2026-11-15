import AIAssistant
import ServiceCatalog
import ServerControl
import SwiftUI

/// Builds read-only contexts from data the app already holds.
@MainActor
enum AIExplain {
    static func problem(_ problem: ServerProblem, facts: [ServerHealthFacts],
                        deployments: [Deployment], title: String) -> AIContext {
        let names = Dictionary(deployments.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let lines = facts.filter { $0.problems.contains(problem) }.map { fact in
            var parts = [names[fact.id] ?? "server"]
            if fact.unreachable { parts.append("unreachable") }
            if let disk = fact.diskFraction { parts.append(String(format: "disk %.0f%% used", disk * 100)) }
            if let down = fact.servicesDown { parts.append("\(down) services need attention") }
            if let pending = fact.updatesPending { parts.append("\(pending) updates waiting") }
            return parts.joined(separator: ", ")
        }
        return AIContext(kind: .problem, title: title,
                         sections: [("Affected servers", lines.joined(separator: "\n"))])
    }

    static func service(name: String, server: String, logs: String) -> AIContext {
        AIContext(kind: .service, title: "\(name) on \(server)", sections: [("Recent logs", logs)])
    }

    static func operation(title: String, error: String?, log: String) -> AIContext {
        AIContext(kind: .operation, title: title,
                  sections: [("Error", error ?? ""), ("Output", log)])
    }
}

/// The "Explain" button, shown only while the module is on.
struct AIExplainButton: View {
    let context: () -> AIContext
    var after: () -> Void = {}
    @ObservedObject private var modules = ModuleSettings.shared

    var body: some View {
        if modules.isOn(.ai) {
            Button {
                AIChatStore.shared.start(context())
                after()
            } label: {
                Label("Explain", systemImage: "sparkles")
            }
        }
    }
}
