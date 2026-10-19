#if DEBUG && os(iOS)
import UIKit

/// Logs late frames while the app runs, for smoothness checks
@MainActor
final class FrameProbe: NSObject {
    private static var running: FrameProbe?
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0

    static func startIfAsked() {
        guard running == nil,
              ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_FRAME_PROBE"] != nil else { return }
        let probe = FrameProbe()
        let link = CADisplayLink(target: probe, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        probe.link = link
        running = probe
    }

    /// Marks the log so gaps match actions
    static func note(_ text: String) {
        guard running != nil else { return }
        print("PROBE \(String(format: "%.3f", CACurrentMediaTime())) \(text)")
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard last > 0 else { return }
        let gap = link.timestamp - last
        let frame = link.duration > 0 ? link.duration : 1.0 / 60
        guard gap > frame * 1.5 else { return }
        print("PROBE \(String(format: "%.3f", link.timestamp)) late \(Int(gap * 1000)) ms")
    }
}
#endif
