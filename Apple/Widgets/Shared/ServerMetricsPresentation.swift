import AppIntents
import Foundation
import SwiftUI
import VPNTunnel

/// Which server a metrics widget is about
struct ServerChoice: AppEntity {
    let id: UUID
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Server" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    static var defaultQuery: ServerChoiceQuery { ServerChoiceQuery() }
}

struct ServerChoiceQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ServerChoice] {
        Self.all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ServerChoice] { Self.all() }

    func defaultResult() async -> ServerChoice? { Self.all().first }

    static func all() -> [ServerChoice] {
        (FleetSnapshotStore().read()?.servers ?? [])
            .filter(\.hasAnyReading)
            .map { ServerChoice(id: $0.id, name: $0.name) }
    }
}

struct ServerSelectionConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Server" }
    static var description: IntentDescription { "Which server to show." }

    @Parameter(title: "Server")
    var server: ServerChoice?

    init() {}
    init(server: ServerChoice?) { self.server = server }
}

enum ServerMetricsPresentation {
    /// A percentage as the widget prints it
    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    static func age(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: return String(localized: "Now")
        case ..<3_600: return String(localized: "\(Int(seconds / 60)) min ago")
        case ..<86_400: return String(localized: "\(Int(seconds / 3_600)) h ago")
        default: return String(localized: "\(Int(seconds / 86_400)) d ago")
        }
    }

    /// The colour of a load bar
    static func tint(_ percent: Double?) -> Color {
        guard let percent else { return .secondary }
        switch percent {
        case ..<70: return .green
        case ..<90: return .orange
        default: return .red
        }
    }
}
