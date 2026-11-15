import PhotosUI
import SwiftUI

/// Glass message field with attach and send buttons
struct AIChatInputBar: View {
    @Binding var draft: String
    @Binding var attachments: [Data]
    let canAttach: Bool
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    static let maxAttachments = 4

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                AIAttachmentStrip(attachments: $attachments)
            }
            HStack(alignment: .bottom, spacing: 6) {
                if canAttach {
                    AIAttachMenu(attachments: $attachments, limit: Self.maxAttachments)
                }
                TextField("Ask about your servers", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 9)
                    .padding(.leading, canAttach ? 0 : 10)
                    .onSubmit { if canSend { onSend() } }
                actionButton
            }
        }
        .padding(6)
        .aiGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var actionButton: some View {
        if isStreaming {
            AIRoundButton(symbol: "stop.fill", fill: .secondary, label: "Stop", action: onStop)
        } else {
            AIRoundButton(symbol: "arrow.up", fill: canSend ? .accentColor : .secondary.opacity(0.35),
                          label: "Send", action: onSend)
                .disabled(!canSend)
        }
    }
}

/// Filled circle with a white symbol
struct AIRoundButton: View {
    let symbol: String
    let fill: Color
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(fill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// "+" menu: photo library or a picture from the clipboard
private struct AIAttachMenu: View {
    @Binding var attachments: [Data]
    let limit: Int
    @State private var picking = false
    @State private var picked: [PhotosPickerItem] = []

    var body: some View {
        Menu {
            Button { picking = true } label: { Label("Photo library", systemImage: "photo.on.rectangle") }
            Button { add(AIClipboard.imageData()) } label: { Label("Paste picture", systemImage: "doc.on.clipboard") }
                .disabled(!AIClipboard.hasImage)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(attachments.count >= limit)
        .accessibilityLabel(Text("Attach a picture"))
        .photosPicker(isPresented: $picking, selection: $picked,
                      maxSelectionCount: max(1, limit - attachments.count), matching: .images)
        .onChange(of: picked) { _, items in load(items) }
    }

    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        picked = []
        Task {
            for item in items {
                add(try? await item.loadTransferable(type: Data.self))
            }
        }
    }

    private func add(_ raw: Data?) {
        guard let raw, attachments.count < limit, let jpeg = AIImageStore.jpeg(from: raw) else { return }
        attachments.append(jpeg)
    }
}

/// Thumbnails waiting to be sent, each with a remove button
private struct AIAttachmentStrip: View {
    @Binding var attachments: [Data]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(attachments.enumerated()), id: \.offset) { index, data in
                    thumbnail(data)
                        .overlay(alignment: .topTrailing) { remove(index) }
                }
            }
            .padding([.top, .horizontal], 4)
        }
    }

    private func thumbnail(_ data: Data) -> some View {
        (AIImageStore.image(data) ?? Image(systemName: "photo"))
            .resizable()
            .scaledToFill()
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func remove(_ index: Int) -> some View {
        Button {
            attachments.remove(at: index)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.6))
                .font(.system(size: 20))
        }
        .buttonStyle(.plain)
        .offset(x: 5, y: -5)
        .accessibilityLabel(Text("Remove"))
    }
}

extension View {
    /// Liquid Glass where available, a material otherwise
    @ViewBuilder
    func aiGlass<S: Shape>(_ shape: S, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, macOS 26.0, *), AppChrome.usesGlass {
            glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: shape)
        } else if let tint {
            background(tint, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.secondary.opacity(0.2)))
        }
    }
}
