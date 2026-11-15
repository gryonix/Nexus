#if DEBUG && os(iOS)
import UIKit

/// Counts frames where a strip's icon moves on its own
@MainActor
final class IconDriftProbe: NSObject {
    private static var running: IconDriftProbe?
    private var link: CADisplayLink?
    private var drifted = 0
    private let readout = UILabel()

    static func startIfAsked() {
        guard running == nil,
              ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_ICON_PROBE"] != nil else { return }
        let probe = IconDriftProbe()
        let link = CADisplayLink(target: probe, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        probe.link = link
        running = probe
    }

    @objc private func tick() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        attachReadout(to: window)
        let strips = Self.strips(in: window)
        let moving = strips.flatMap(Self.movingIcons)
        if !moving.isEmpty {
            drifted += 1
            Self.record(moving)
        }
        readout.accessibilityValue = "\(drifted)"
    }

    private var overlay: UIWindow?

    /// An invisible label in its own window for UI tests
    private func attachReadout(to window: UIWindow) {
        guard overlay == nil, let scene = window.windowScene else { return }
        let overlay = UIWindow(windowScene: scene)
        overlay.frame = CGRect(x: 0, y: 0, width: 4, height: 4)
        overlay.windowLevel = .alert + 1
        overlay.isUserInteractionEnabled = false
        readout.frame = overlay.bounds
        readout.alpha = 0.02
        readout.isAccessibilityElement = true
        readout.accessibilityIdentifier = "probe.iconDrift"
        readout.accessibilityLabel = "icon drift"
        overlay.addSubview(readout)
        overlay.isHidden = false
        self.overlay = overlay
    }

    private static func strips(in view: UIView) -> [UIView] {
        if view is UISegmentedControl || view is SegmentStripView || view is UITabBar { return [view] }
        return view.subviews.flatMap(strips)
    }

    /// Writes what moved to the app's temporary folder
    private static func record(_ views: [UIView]) {
        let lines = views.map { view -> String in
            let shown = view.layer.presentation()
            let image = (view as? UIImageView)?.image.map { "\($0.size) symbol=\($0.isSymbolImage)" } ?? "label"
            return "\(type(of: view)) \(image) model=\(view.layer.position) shown=\(shown?.position ?? .zero) "
                + "bounds=\(view.layer.bounds.size)/\(shown?.bounds.size ?? .zero) keys=\(view.layer.animationKeys() ?? [])\n"
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("icon-drift.txt")
        let data = Data(lines.joined().utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// Icons and labels whose own frame is animating
    private static func movingIcons(in strip: UIView) -> [UIView] {
        movable(in: strip).filter { view in
            guard let shown = view.layer.presentation() else { return false }
            let model = view.layer
            return abs(shown.position.x - model.position.x) > 0.5
                || abs(shown.position.y - model.position.y) > 0.5
                || abs(shown.bounds.width - model.bounds.width) > 0.5
                || abs(shown.bounds.height - model.bounds.height) > 0.5
        }
    }

    private static func movable(in view: UIView) -> [UIView] {
        let own: [UIView] = view is UIImageView || view is UILabel ? [view] : []
        return own + view.subviews.flatMap(movable)
    }
}
#endif
