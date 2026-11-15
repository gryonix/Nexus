import AppIntents
import SwiftUI
import VPNTunnel
import WidgetKit

@available(iOS 18.0, macOS 26.0, *)
struct ServerStatusControl: ControlWidget {
    static let kind = "gryonixNexus.ServerControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: Provider()) { server in
            ControlWidgetButton(action: OpenServerFromControlIntent(serverID: server?.id)) {
                Label(server?.name ?? String(localized: "Servers"), systemImage: "server.rack")
            }
        }
        .displayName("Server status")
        .description("Opens the app on a server.")
    }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: ServerControlConfiguration) -> ServerChoice? {
            configuration.server
        }

        func currentValue(configuration: ServerControlConfiguration) async throws -> ServerChoice? {
            configuration.server ?? ServerChoiceQuery.all().first
        }
    }
}
