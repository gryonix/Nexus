import ServerControl
import SwiftTerm
import SwiftUI

/// The emulator itself, wrapped for SwiftUI
@available(macOS 15.0, *)
struct TerminalHostView {
    @ObservedObject var controller: TerminalController
    var look = TerminalAppearance()
    var theme = TerminalThemes.builtIn[0]
    var accessory = TerminalAccessoryLayout()
    var zoomTo: (Double) -> Void = { _ in }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let controller: TerminalController
        var zoomTo: (Double) -> Void = { _ in }
        var startSize = 13.0
        var currentSize = 13.0
        var shownKeys: TerminalAccessoryLayout?

        init(controller: TerminalController) {
            self.controller = controller
        }

        func pinched(scale: Double, began: Bool) {
            if began { startSize = currentSize }
            zoomTo(min(max(startSize * scale, TerminalAppearance.fontSizeRange.lowerBound),
                        TerminalAppearance.fontSizeRange.upperBound))
        }

        #if os(iOS)
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            pinched(scale: Double(gesture.scale), began: gesture.state == .began)
        }
        #else
        @objc func pinch(_ gesture: NSMagnificationGestureRecognizer) {
            pinched(scale: 1 + Double(gesture.magnification), began: gesture.state == .began)
        }
        #endif

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            MainActor.assumeIsolated { controller.send(data) }
        }

        /// The window changed — rotation, or the keyboard coming up
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            MainActor.assumeIsolated { controller.resize(columns: newCols, rows: newRows) }
        }

        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        /// Deliberately silent
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func clipboardRead(source: TerminalView) -> Data? { nil }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    fileprivate func makeTerminal(coordinator: Coordinator) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = coordinator
        coordinator.zoomTo = zoomTo
        #if os(iOS)
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: coordinator,
                                                           action: #selector(Coordinator.pinch(_:))))
        #else
        view.addGestureRecognizer(NSMagnificationGestureRecognizer(target: coordinator,
                                                                   action: #selector(Coordinator.pinch(_:))))
        #endif
        coordinator.currentSize = look.fontSize
        TerminalLook.apply(look, theme: theme, to: view)
        #if os(iOS)
        view.inputAccessoryView = TerminalKeyAccessory(terminal: view, layout: accessory)
        #endif
        DispatchQueue.main.async {
            MainActor.assumeIsolated { controller.attach(view) }
        }
        return view
    }
}

#if os(iOS)
@available(macOS 15.0, *)
extension TerminalHostView: UIViewRepresentable {
    func makeUIView(context: Context) -> TerminalView {
        makeTerminal(coordinator: context.coordinator)
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        context.coordinator.currentSize = look.fontSize
        context.coordinator.zoomTo = zoomTo
        TerminalLook.apply(look, theme: theme, to: uiView)
        if context.coordinator.shownKeys != accessory {
            context.coordinator.shownKeys = accessory
            (uiView.inputAccessoryView as? TerminalKeyAccessory)?.show(accessory)
        }
    }
}
#elseif os(macOS)
@available(macOS 15.0, *)
extension TerminalHostView: NSViewRepresentable {
    func makeNSView(context: Context) -> TerminalView {
        makeTerminal(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        context.coordinator.currentSize = look.fontSize
        context.coordinator.zoomTo = zoomTo
        TerminalLook.apply(look, theme: theme, to: nsView)
    }
}
#endif
