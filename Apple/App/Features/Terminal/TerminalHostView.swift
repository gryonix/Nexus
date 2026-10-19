import SwiftTerm
import SwiftUI

/// The emulator itself, wrapped for SwiftUI
@available(macOS 15.0, *)
struct TerminalHostView {
    @ObservedObject var controller: TerminalController

    final class Coordinator: NSObject, TerminalViewDelegate {
        let controller: TerminalController

        init(controller: TerminalController) {
            self.controller = controller
        }

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

    func updateUIView(_ uiView: TerminalView, context: Context) {}
}
#elseif os(macOS)
@available(macOS 15.0, *)
extension TerminalHostView: NSViewRepresentable {
    func makeNSView(context: Context) -> TerminalView {
        makeTerminal(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {}
}
#endif
