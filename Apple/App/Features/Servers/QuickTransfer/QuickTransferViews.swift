import ServerControl
import SwiftUI

/// The sending side: QR code, the question, the dots
struct QuickTransferSendView: View {
    @StateObject var model: QuickTransferSendModel
    @Environment(\.dismiss) private var dismiss
    @State private var scatteredAt: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    stage
                    caption
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .screenTitle("Send by QR code")
            .raisedNavigationTitle()
            .toolbar { closeButton }
            #if os(macOS)
            .frame(minWidth: 440, minHeight: 600)
            #endif
        }
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: model.phase) { _, phase in
            if case .asking = phase { scatteredAt = Date() }
            if case .showing = phase { scatteredAt = nil }
        }
    }

    @ViewBuilder
    private var stage: some View {
        switch model.phase {
        case .starting:
            ProgressView().frame(height: 300)
        case .showing, .asking:
            QuickTransferQRView(modules: model.modules, scatteredAt: scatteredAt)
                .frame(maxWidth: 320)
                .overlay { if case .asking(_, let code) = model.phase { QuickTransferCodeBadge(code: code) } }
        case .sending:
            QuickTransferDotsView(from: QuickTransferDevice.current, to: "iphone").padding(.vertical, 60)
        case .sent:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72)).foregroundStyle(.green)
                .symbolEffect(.bounce, value: model.phase)
                .sensoryFeedback(.success, trigger: model.phase)
                .padding(.vertical, 40)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56)).foregroundStyle(.orange).padding(.vertical, 40)
        }
    }

    @ViewBuilder
    private var caption: some View {
        switch model.phase {
        case .starting:
            Text("Preparing…").foregroundStyle(.secondary)
        case .showing:
            QuickTransferHint(title: "Scan this code with Nexus on the other device",
                              detail: "There: Servers › Import server › QR code. It works on the same Wi-Fi, or over Bluetooth when the devices are close.")
        case .asking(let device, _):
            askingCaption(device)
        case .sending(let device):
            Text(verbatim: UIL10n.string("Sending to “%@”…", device)).foregroundStyle(.secondary)
        case .sent(let device, _):
            sentCaption(device)
        case .failed(let message):
            failedCaption(message)
        }
    }

    private func askingCaption(_ device: String) -> some View {
        VStack(spacing: 14) {
            Text(verbatim: UIL10n.string("“%@” wants to receive the servers", device)).font(.headline)
            Text("Allow it only if the other device shows the same code.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Decline", role: .cancel) { model.decline() }.secondaryActionButtonStyle()
                Button("Allow") { model.allow() }.prominentActionButtonStyle()
                    .accessibilityIdentifier("quicktransfer.allow")
            }
            .controlSize(.large)
        }
    }

    private func sentCaption(_ device: String) -> some View {
        VStack(spacing: 14) {
            Text(verbatim: UIL10n.string("Sent to “%@”", device)).font(.headline)
            Button("Done") { dismiss() }.prominentActionButtonStyle().controlSize(.large)
        }
    }

    private func failedCaption(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text(verbatim: message).multilineTextAlignment(.center)
            Button("Try again") { Task { await model.start() } }.prominentActionButtonStyle()
        }
    }

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(isFinished ? "Done" : "Cancel") { dismiss() }
        }
    }

    private var isFinished: Bool {
        if case .sent = model.phase { return true }
        return false
    }
}

/// The receiving side: camera, the code, the arrival
struct QuickTransferReceiveView: View {
    @StateObject var model: QuickTransferReceiveModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    stage
                    caption
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .screenTitle("Receive by QR code")
            .raisedNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isFinished ? "Done" : "Cancel") { dismiss() }
                }
            }
            #if os(macOS)
            .frame(minWidth: 440, minHeight: 600)
            #endif
        }
        .onDisappear { model.stop() }
    }

    private var isFinished: Bool {
        if case .received = model.phase { return true }
        return false
    }

    @ViewBuilder
    private var stage: some View {
        switch model.phase {
        case .scanning:
            QuickTransferScannerView { model.scanned($0) }
        case .connecting, .receiving:
            QuickTransferDotsView(from: "qrcode", to: QuickTransferDevice.current).padding(.vertical, 60)
        case .confirming(let code):
            QuickTransferCodeBadge(code: code).padding(.vertical, 40)
        case .received(let names):
            QuickTransferArrivalView(names: names)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56)).foregroundStyle(.orange).padding(.vertical, 40)
        }
    }

    @ViewBuilder
    private var caption: some View {
        switch model.phase {
        case .scanning:
            QuickTransferHint(title: "Point the camera at the code on the other device",
                              detail: "There: Servers › Export servers › QR code.")
        case .connecting:
            Text("Connecting…").foregroundStyle(.secondary)
        case .confirming:
            QuickTransferHint(title: "Check that the other device shows this code",
                              detail: "Then allow the transfer there.")
        case .receiving:
            Text("Receiving…").foregroundStyle(.secondary)
        case .received:
            Button("Done") { dismiss() }.prominentActionButtonStyle().controlSize(.large)
        case .failed(let message):
            VStack(spacing: 14) {
                Text(verbatim: message).multilineTextAlignment(.center)
                Button("Try again") { model.retry() }.prominentActionButtonStyle()
            }
        }
    }
}

/// Title and a quieter line under it
struct QuickTransferHint: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }
}

/// The four-digit check code, large
struct QuickTransferCodeBadge: View {
    let code: String

    var body: some View {
        Text(verbatim: code)
            .font(.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit())
            .kerning(10)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .transition(.scale.combined(with: .opacity))
            .accessibilityIdentifier("quicktransfer.code")
    }
}
