import SwiftUI

/// Blocks the screen until the server answers
struct PleaseWaitOverlay: ViewModifier {
    let isPresented: Bool
    /// Progress text shown under the note
    var detail = ""

    func body(content: Content) -> some View {
        content
            .disabled(isPresented)
            .overlay {
                if isPresented {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        card
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isPresented)
    }

    private var card: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Please wait")
                .font(.headline)
            Text("The server is applying the change. Tapping again now would undo it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !detail.isEmpty {
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .padding(24)
        .frame(maxWidth: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("please-wait")
    }
}

extension View {
    func pleaseWait(_ isPresented: Bool, detail: String = "") -> some View {
        modifier(PleaseWaitOverlay(isPresented: isPresented, detail: detail))
    }
}
