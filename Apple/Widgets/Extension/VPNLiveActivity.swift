#if os(iOS)
import ActivityKit
import SwiftUI
import VPNTunnel
import WidgetKit

struct VPNLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TunnelActivityAttributes.self) { context in
            let model = VPNIsland.model(context)
            VPNLockScreenCard(model: model) { VPNStopButton(model: model) }
                .environment(\.colorScheme, .dark)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let model = VPNIsland.model(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VPNExpandedLeading(model: model)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VPNStopButton(model: model)
                        .padding(.trailing, IslandLayout.inset)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VPNExpandedBottom(model: model)
                }
            } compactLeading: {
                VPNCompactLeading(model: model)
            } compactTrailing: {
                VPNCompactTrailing(model: model)
            } minimal: {
                VPNCompactLeading(model: model)
            }
            .keylineTint(model.tint)
            .widgetURL(AppLink.url(for: .tunnel))
        }
    }
}

/// Sizes and the model shared by the island's regions
enum VPNIsland {
    static func model(_ context: ActivityViewContext<TunnelActivityAttributes>) -> VPNIslandModel {
        VPNIslandModel(status: context.state.status,
                       statistics: context.state.statistics,
                       startedAt: context.attributes.startedAt,
                       serverName: context.attributes.serverName,
                       protocolName: context.attributes.protocolName,
                       profileName: context.attributes.profileName,
                       isSimulated: context.attributes.isSimulated,
                       style: context.attributes.style ?? .standard,
                       stopArmed: context.state.stopArmed == true)
    }
}

/// The round stop: the first tap asks, the second disconnects
private struct VPNStopButton: View {
    let model: VPNIslandModel

    var body: some View {
        IslandStopButton(isArmed: model.stopArmed, tint: model.tint) { face in
            Button(intent: DisconnectTunnelFromCardIntent()) { face }
                .buttonStyle(.plain)
        }
    }
}

#endif
