#if os(iOS)
import ActivityKit
import SwiftUI
import VPNTunnel
import WidgetKit

struct OperationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OperationActivityAttributes.self) { context in
            lockScreen(context)
                .environment(\.colorScheme, .dark)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(AppLink.url(for: OperationPresentation.destination(of: context.attributes)))
        } dynamicIsland: { context in
            let outcome = OperationPresentation.outcome(context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedIslandLeading(context: context, outcome: outcome)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if outcome == .running, Self.canStop(context) {
                        OperationStopButton(context: context)
                            .padding(.trailing, Self.islandInset)
                            .frame(maxHeight: .infinity, alignment: .center)
                    } else if outcome == .running {
                        ExpandedIslandFigures(state: context.state, attributes: context.attributes,
                                              tint: OperationPresentation.tint(outcome))
                            .padding(.trailing, Self.islandInset)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if outcome != .running {
                        FinishedIslandSummary(context: context, outcome: outcome)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedIslandBottom(context: context, outcome: outcome)
                }
            } compactLeading: {
                CompactIslandGlyph { diameter in
                    OperationRunGlyph(state: context.state, diameter: diameter)
                }
            } compactTrailing: {
                if let percent = OperationPresentation.percentText(context.state) {
                    CompactIslandPercent(text: percent,
                                         tint: OperationPresentation.tint(outcome))
                } else if OperationPresentation.showsRunningClock(context.state) {
                    CompactIslandTimer(since: context.attributes.startedAt)
                }
            } minimal: {
                CompactIslandGlyph { diameter in
                    OperationRunGlyph(state: context.state, diameter: diameter)
                }
            }
            .widgetURL(AppLink.url(for: OperationPresentation.destination(of: context.attributes)))
        }
    }

    static let expandedTimerWidth: CGFloat = 44

    static func canStop(_ context: ActivityViewContext<OperationActivityAttributes>) -> Bool {
        let attributes = context.attributes
        return attributes.canStop == true
            && (attributes.operationID != nil || (attributes.jobID != nil && attributes.serverID != nil))
    }
    /// Keeps content clear of the island's rounded sides
    static let islandInset: CGFloat = 8
    static let lockScreenTimerWidth: CGFloat = 64

    private func lockScreen(_ context: ActivityViewContext<OperationActivityAttributes>) -> some View {
        let outcome = OperationPresentation.outcome(context.state)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(verbatim: context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: OperationPresentation.symbol(outcome))
                        .foregroundStyle(OperationPresentation.tint(outcome))
                }
                .layoutPriority(1)
                Spacer(minLength: 6)
                if OperationPresentation.showsRunningClock(context.state) {
                    TunnelSessionTimer(since: context.attributes.startedAt,
                                       font: .subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: Self.lockScreenTimerWidth, alignment: .trailing)
                }
                if outcome == .running, Self.canStop(context) {
                    OperationStopButton(context: context)
                }
            }
            Text(verbatim: context.attributes.serverName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(verbatim: StepLine.text(context.state))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            OperationBar(context: context, outcome: outcome)
                .padding(.top, 2)
            if context.state.stopArmed == true, outcome == .running {
                StopQuestion()
            }
            if outcome == .failed {
                FailedCardActions(context: context)
                    .padding(.top, 4)
            }
            if context.isStale, !context.state.isFinished {
                Text(verbatim: OperationPresentation.staleNote())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding()
    }
}
private struct ExpandedIslandFigures: View {
    let state: OperationActivityAttributes.ContentState
    let attributes: OperationActivityAttributes
    let tint: Color

    private var startedAt: Date { attributes.startedAt }

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: OperationPresentation.stepText(state) ?? OperationPresentation.percentText(state) ?? "—")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
            if OperationPresentation.showsRunningClock(state) {
                TunnelSessionTimer(since: startedAt, font: .caption.monospacedDigit())
                    .frame(width: OperationLiveActivity.expandedTimerWidth, alignment: .trailing)
            }
        }
    }
}

/// The current line, led by the step counter
enum StepLine {
    static func text(_ state: OperationActivityAttributes.ContentState) -> String {
        let detail = OperationPresentation.detail(state)
        guard let step = OperationPresentation.stepText(state) else { return detail }
        return "\(step) · \(detail)"
    }
}

/// The round stop: the first tap asks, the second stops
private struct OperationStopButton: View {
    let context: ActivityViewContext<OperationActivityAttributes>

    var body: some View {
        let attributes = context.attributes
        IslandStopButton(isArmed: context.state.stopArmed == true,
                         tint: OperationPresentation.tint(.running)) { face in
            if let id = attributes.operationID {
                Button(intent: StopOperationIntent(operationID: id)) { face }
                    .buttonStyle(.plain)
            } else if let job = attributes.jobID, let server = attributes.serverID {
                Button(intent: StopJobIntent(jobID: job, serverID: server)) { face }
                    .buttonStyle(.plain)
            }
        }
    }
}

/// Asks for the second tap under an armed stop
private struct StopQuestion: View {
    var body: some View {
        Text("Tap stop again to stop")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.red)
    }
}

/// "Try again" and "Details" under a failed run
private struct FailedCardActions: View {
    let context: ActivityViewContext<OperationActivityAttributes>

    var body: some View {
        if let id = context.attributes.operationID {
            HStack(spacing: 8) {
                if context.state.canRetry == true {
                    Button(intent: RetryOperationIntent(operationID: id)) {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                    .tint(.orange)
                }
                Link(destination: AppLink.url(for: .operation(id))) {
                    Label("Details", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderedProminent)
        } else if let job = context.attributes.jobID {
            Link(destination: AppLink.url(for: .job(job))) {
                Label("Details", systemImage: "list.bullet.rectangle")
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
        }
    }
}

/// The share of steps the server has finished
private struct OperationBar: View {
    let context: ActivityViewContext<OperationActivityAttributes>
    let outcome: OperationPresentation.Outcome

    var body: some View {
        let tint = OperationPresentation.tint(outcome)
        if let value = OperationPresentation.barValue(context.state) {
            ProgressView(value: value).tint(tint)
        }
    }
}

/// The finished run's large mark
private struct FinishedIslandGlyph: View {
    let outcome: OperationPresentation.Outcome

    var body: some View {
        Image(systemName: OperationPresentation.symbol(outcome))
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(OperationPresentation.tint(outcome))
            .padding(.leading, 4)
    }
}

/// The outcome, the operation and the server
private struct FinishedIslandSummary: View {
    let context: ActivityViewContext<OperationActivityAttributes>
    let outcome: OperationPresentation.Outcome

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: OperationPresentation.headline(context.state))
                .font(.headline)
                .foregroundStyle(OperationPresentation.tint(outcome))
                .lineLimit(1)
            Text(verbatim: context.attributes.title)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(verbatim: context.attributes.serverName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Server, current step and the bar under them
private struct ExpandedIslandDetail: View {
    let context: ActivityViewContext<OperationActivityAttributes>
    let outcome: OperationPresentation.Outcome

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: context.attributes.serverName)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
            Text(verbatim: StepLine.text(context.state))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            OperationBar(context: context, outcome: outcome)
            if context.state.stopArmed == true, outcome == .running {
                StopQuestion()
            }
            if context.isStale, !context.state.isFinished {
                Text(verbatim: OperationPresentation.staleNote())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
/// Expanded island's left side: title and figures, or outcome
private struct ExpandedIslandLeading: View {
    let context: ActivityViewContext<OperationActivityAttributes>
    let outcome: OperationPresentation.Outcome

    var body: some View {
        if outcome == .running {
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(verbatim: context.attributes.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } icon: {
                    CompactIslandGlyph { diameter in
                        OperationRunGlyph(state: context.state, diameter: diameter)
                    }
                }
                if OperationLiveActivity.canStop(context) {
                    ExpandedIslandFigures(state: context.state, attributes: context.attributes,
                                          tint: OperationPresentation.tint(outcome))
                }
            }
            .padding(.leading, OperationLiveActivity.islandInset)
            .frame(maxHeight: .infinity, alignment: .center)
        } else {
            FinishedIslandGlyph(outcome: outcome)
        }
    }
}

/// The expanded island's bottom: progress detail, or why it failed
private struct ExpandedIslandBottom: View {
    let context: ActivityViewContext<OperationActivityAttributes>
    let outcome: OperationPresentation.Outcome

    var body: some View {
        if outcome == .running {
            ExpandedIslandDetail(context: context, outcome: outcome)
                .padding(.horizontal, OperationLiveActivity.islandInset)
                .padding(.bottom, 4)
        } else if outcome == .failed {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: OperationPresentation.detail(context.state))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                FailedCardActions(context: context)
            }
            .padding(.horizontal, OperationLiveActivity.islandInset)
        }
    }
}
#endif
