#if DEBUG
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum CardResizeProbe {
    /// Seconds between flips, or nil when the probe is off
    static var interval: TimeInterval? {
        guard let raw = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_CARD_RESIZE"] else {
            return nil
        }
        return TimeInterval(raw) ?? 1.5
    }

    static var isEnabled: Bool { interval != nil }

    static var flipsOneCard: Bool {
        ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_CARD_RESIZE_ONE"] != nil
    }

    static var slowFactor: Double {
        guard let raw = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_CARD_RESIZE_SLOW"],
              let factor = Double(raw), factor > 0 else { return 1 }
        return factor
    }

    private static let started = Date()

    static var now: TimeInterval { Date().timeIntervalSince(started) }

    static func record(_ size: CGSize, of name: String) {
        let line = String(format: "CARDFRAME %@ %.2f %.2f %.4f", name, size.width, size.height,
                          Date().timeIntervalSince(started))
        NSLog("%@", line)
        trace.write(Data((line + "\n").utf8))
    }

    private static let trace: FileHandle = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cardframe.log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return (try? FileHandle(forWritingTo: url)) ?? .nullDevice
    }()
}

#if canImport(UIKit)
final class ProbeLayerSampler: UIView {
    private let name: String
    private var link: CADisplayLink?
    private var last: CGSize = .zero

    init(name: String) {
        self.name = name
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        let size = (layer.presentation() ?? layer).bounds.size
        guard abs(size.width - last.width) > 0.01 || abs(size.height - last.height) > 0.01 else {
            return
        }
        last = size
        CardResizeProbe.record(size, of: name)
    }
}

struct ProbeMarker: UIViewRepresentable {
    let name: String
    func makeUIView(context: Context) -> ProbeLayerSampler { ProbeLayerSampler(name: name) }
    func updateUIView(_ view: ProbeLayerSampler, context: Context) {}
}

#endif

extension View {
    @ViewBuilder
    func cardResizeProbe(_ name: String) -> some View {
        #if canImport(UIKit)
        if CardResizeProbe.isEnabled {
            background(ProbeMarker(name: name))
        } else {
            self
        }
        #else
        self
        #endif
    }
}
#endif
