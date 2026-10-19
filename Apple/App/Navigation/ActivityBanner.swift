import ServerControl
import SwiftUI

struct ActivityBanner: View {
    var surface: BannerSurface = .systemProvided

    static let classicBarInset: CGFloat = 20

    @StateObject private var installs = InstallSessionRegistry.shared
    @StateObject private var operations = RunningOperationsRegistry.shared
    @StateObject private var navigator = AppNavigator.shared
    /// Agent installs this device started and has not seen through
    @StateObject private var pending = PendingAgentInstalls.shared

    /// Nothing running anywhere
    private var isIdle: Bool {
        pending.pending.isEmpty && installs.installing.isEmpty && operations.entries.isEmpty
    }

    var body: some View {
        if isIdle {
            EmptyView()
        } else {
            rows
        }
    }

    /// Pending installs no operation already shows
    private var pendingRows: [PendingAgentInstalls.Pending] {
        pending.pending.filter { row in
            !operations.entries.contains { $0.state.title.contains(row.serviceName) }
        }
    }

    private var rowCount: Int {
        installs.installing.count + pendingRows.count + operations.entries.count
    }

    /// The system accessory fits one row; the busiest goes there
    private var lead: Lead? {
        if let running = operations.entries.last(where: { !$0.state.isFinished }) { return .operation(running) }
        if let deployment = installs.installing.first { return .install(deployment) }
        if let row = pendingRows.first { return .pending(row) }
        return operations.entries.last.map { .operation($0) }
    }

    private enum Lead {
        case install(Deployment)
        case pending(PendingAgentInstalls.Pending)
        case operation(RunningOperationsRegistry.Entry)
    }

    @ViewBuilder
    private var rows: some View {
        Group {
            if surface == .systemProvided {
                if let lead { row(for: lead, more: rowCount - 1) }
            } else {
                VStack(spacing: 6) {
                    ForEach(installs.installing) { row(for: .install($0), more: 0) }
                    ForEach(pendingRows) { row(for: .pending($0), more: 0) }
                    ForEach(operations.entries) { row(for: .operation($0), more: 0) }
                }
            }
        }
        .padding(.bottom, surface == .ownCapsule ? 6 : 0)
        .animation(.smooth(duration: 0.3), value: pending.pending.count)
        .animation(.smooth(duration: 0.3), value: installs.installing.count)
        .animation(.smooth(duration: 0.3), value: operations.entries.count)
    }

    @ViewBuilder
    private func row(for lead: Lead, more: Int) -> some View {
        switch lead {
        case .install(let deployment):
            BannerRow(title: UIL10n.string("Installing %@…", deployment.name),
                      subtitle: nil, status: .running, surface: surface, more: more) {
                navigator.resumeInstall = deployment
            }
        case .pending(let row):
            BannerRow(title: UIL10n.string("Installing %@…", row.serviceName),
                      subtitle: UIL10n.string("Running on the server. Open to watch it."),
                      status: .running, surface: surface, more: more) {
                navigator.openServerID = row.deploymentID
            }
        case .operation(let entry):
            OperationBannerRow(state: entry.state, surface: surface, more: more) {
                if let deployment = entry.state.reattachDeployment {
                    navigator.reopenInstallResult = deployment
                } else {
                    operations.present(entry.state)
                }
            } onDismiss: {
                operations.dismiss(entry.id)
            } onFinished: {
                operations.scheduleDismissal(of: entry.id)
            }
        }
    }
}

enum BannerStatus { case running, done, failed }

private struct OperationBannerRow: View {
    @ObservedObject var state: LongOperationState
    var surface: BannerSurface = .systemProvided
    var more = 0
    let action: () -> Void
    let onDismiss: () -> Void
    let onFinished: () -> Void

    var body: some View {
        BannerRow(title: state.title,
                  subtitle: state.errorMessage ?? state.progressText,
                  status: status,
                  surface: surface,
                  more: more,
                  action: action,
                  onDismiss: onDismiss)
            .onChange(of: state.isFinished, initial: true) { _, finished in
                if finished { onFinished() }
            }
    }

    private var status: BannerStatus {
        if !state.isFinished { return .running }
        return state.errorMessage != nil ? .failed : .done
    }
}

/// How a row draws its own surface
enum BannerSurface {
    case systemProvided
    case ownCapsule
}

/// The row itself — one layout for install and every operation
private struct BannerRow: View {
    let title: String
    let subtitle: String?
    let status: BannerStatus
    var surface: BannerSurface = .systemProvided
    /// Rows hidden behind this one
    var more = 0
    let action: () -> Void
    /// Swiping the row away
    var onDismiss: (() -> Void)?
    @State private var offset: CGFloat = 0

    private static let dismissDistance: CGFloat = 60

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                let accent: Color = surface == .ownCapsule ? .white : tint
                switch status {
                case .running: ProgressView().controlSize(.small).tint(accent)
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(verbatim: subtitle)
                            .font(.caption)
                            .opacity(0.85)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if more > 0 {
                    Text(verbatim: "+\(more)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .opacity(0.85)
                }
                Text("Open")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(surface == .ownCapsule ? AnyShapeStyle(.white)
                                                            : AnyShapeStyle(Color.accentColor))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(surface == .ownCapsule ? AnyShapeStyle(.white)
                                                            : AnyShapeStyle(.secondary))
            }
            .foregroundStyle(surface == .ownCapsule ? AnyShapeStyle(.white)
                                                     : AnyShapeStyle(.primary))
            .padding(.horizontal, surface == .ownCapsule ? 16 : 4)
            .padding(.vertical, surface == .ownCapsule ? 10 : 2)
            .frame(maxWidth: .infinity)
            .background {
                if surface == .ownCapsule { Capsule().fill(tint) }
            }
        }
        .buttonStyle(.plain)
        .offset(x: offset)
        .opacity(opacity)
        .gesture(onDismiss.map { dismiss in
            DragGesture(minimumDistance: 20)
                .onChanged { offset = $0.translation.width }
                .onEnded { value in
                    if abs(value.translation.width) > Self.dismissDistance {
                        withAnimation(.smooth(duration: 0.2)) {
                            offset = value.translation.width > 0 ? 500 : -500
                        }
                        dismiss()
                    } else {
                        withAnimation(.smooth(duration: 0.2)) { offset = 0 }
                    }
                }
        })
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var opacity: Double {
        max(1 - Double(abs(offset)) / 200, 0)
    }

    private var tint: Color {
        switch status {
        case .running: return .accentColor
        case .done: return .green
        case .failed: return .red
        }
    }
}
