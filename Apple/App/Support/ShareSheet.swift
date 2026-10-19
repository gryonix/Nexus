import SwiftUI

#if os(iOS)
import UIKit

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#if os(macOS)
import AppKit

private struct SharingServicePickerPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    let items: [Any]

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard isPresented, !context.coordinator.isShowing, nsView.window != nil else { return }
        context.coordinator.isShowing = true
        DispatchQueue.main.async {
            let picker = NSSharingServicePicker(items: items)
            picker.delegate = context.coordinator
            picker.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .minY)
        }
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        @Binding var isPresented: Bool
        var isShowing = false

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }

        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                                   didChoose service: NSSharingService?) {
            isShowing = false
            isPresented = false
        }
    }
}
#endif

private struct ShareSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let items: [Any]

    func body(content: Content) -> some View {
        #if os(iOS)
        content.sheet(isPresented: $isPresented) {
            ActivityShareSheet(items: items) { isPresented = false }
        }
        #elseif os(macOS)
        content.background(SharingServicePickerPresenter(isPresented: $isPresented, items: items))
        #else
        content
        #endif
    }
}

extension View {
    func shareSheet(isPresented: Binding<Bool>, items: [Any]) -> some View {
        modifier(ShareSheetModifier(isPresented: isPresented, items: items))
    }
}
