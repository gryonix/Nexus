import ServiceCatalog
import SwiftUI

/// Adds a swap file right after the connection check
struct SwapRow: View {
    let target: InstallViewModel.Target
    let onAdd: (Int) -> Void
    @State private var size = 2

    var body: some View {
        if target.connection == .ok, let hardware = target.hardware {
            LabeledContent("Swap now") { Text(verbatim: Self.current(hardware.swapBytes)) }
            switch target.swap {
            case .adding:
                HStack { ProgressView().controlSize(.small); Text("Adding swap…") }
            case .idle, .failed:
                WheelRow(title: "Add swap",
                         choices: Array(SwapPlan.wheel.dropFirst()), selection: $size) {
                    Text(verbatim: UIL10n.string("%@ GB", "\($0)")).monospacedDigit()
                }
                Button("Add swap…", systemImage: "memorychip") { onAdd(size) }
                    .rowActionButtonStyle()
            }
            if case .failed(let message) = target.swap {
                Text(verbatim: message).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

extension SwapRow {
    static func current(_ bytes: Int64) -> String {
        bytes > 0 ? StorageText.bytes(bytes) : UIL10n.string("None")
    }
}
