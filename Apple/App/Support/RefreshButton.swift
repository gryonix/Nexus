import SwiftUI

/// Small circular arrow that re-reads one row's state
struct RefreshButton: View {
    let label: LocalizedStringKey
    var isBusy = false
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            mark
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(Text(label))
    }

    @ViewBuilder private var mark: some View {
        if isBusy {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: "arrow.clockwise")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
