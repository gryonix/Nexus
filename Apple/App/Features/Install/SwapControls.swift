import ServiceCatalog
import SwiftUI

/// Adds a swap file right after the connection check
struct SwapRow: View {
    let target: InstallViewModel.Target
    let onAdd: (Int) -> Void
    @State private var asking = false
    @State private var custom = false

    var body: some View {
        if target.connection == .ok, let hardware = target.hardware {
            LabeledContent("Swap now") { Text(verbatim: Self.current(hardware.swapBytes)) }
            switch target.swap {
            case .adding:
                HStack { ProgressView().controlSize(.small); Text("Adding swap…") }
            case .idle, .failed:
                Button("Add swap…", systemImage: "memorychip") { asking = true }
                    .rowActionButtonStyle()
                    .confirmationDialog("Add swap", isPresented: $asking, titleVisibility: .visible) {
                        ForEach(SwapPlan.sizes, id: \.self) { size in
                            Button(UIL10n.string("%@ GB", "\(size)")) { onAdd(size) }
                        }
                        Button("Other size…") { custom = true }
                    } message: {
                        Text("Swap now: \(Self.current(target.hardware?.swapBytes ?? 0)). A swap file lets a small server run what needs more memory, only slower. It stays after a restart.")
                    }
                    .customSwapSize(isPresented: $custom, onSet: onAdd)
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

/// Asks for a swap size in whole gigabytes
struct CustomSwapSize: ViewModifier {
    @Binding var isPresented: Bool
    let onSet: (Int) -> Void
    @State private var text = ""

    func body(content: Content) -> some View {
        content.alert("Swap size", isPresented: $isPresented) {
            TextField(text: $text) { Text(verbatim: "GB") }
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Button("Set") {
                if let size = Int(text.trimmingCharacters(in: .whitespaces)), SwapPlan.allowed.contains(size) {
                    onSet(size)
                }
                text = ""
            }
            Button("Cancel", role: .cancel) { text = "" }
        } message: {
            Text("From 1 to 256 GB.")
        }
    }
}

extension View {
    func customSwapSize(isPresented: Binding<Bool>, onSet: @escaping (Int) -> Void) -> some View {
        modifier(CustomSwapSize(isPresented: isPresented, onSet: onSet))
    }
}
