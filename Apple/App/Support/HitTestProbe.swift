#if DEBUG && os(iOS)
import SwiftUI
import UIKit

struct HitTestProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEBUG_HITTEST"] != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.report() }
        }

        private func report() {
            guard let window else { return }
            var out = "HITTEST width=\(window.bounds.width) height=\(window.bounds.height)\n"
            let x = window.bounds.midX
            for y in stride(from: 100.0, through: window.bounds.height - 120, by: 20.0) {
                let point = CGPoint(x: x, y: y)
                let hit = window.hitTest(point, with: nil)
                let chain = Self.chain(of: hit)
                out += String(format: "  y=%4.0f  %@\n", y, chain)
            }
            FileHandle.standardError.write(Data(out.utf8))
        }

        private static func chain(of view: UIView?) -> String {
            var names: [String] = []
            var current = view
            for _ in 0..<3 {
                guard let node = current else { break }
                names.append(String(describing: type(of: node)))
                current = node.superview
            }
            return names.joined(separator: " ← ")
        }
    }
}
#endif
