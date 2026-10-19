#if os(iOS)
import SwiftUI
import UIKit

@MainActor
final class SegmentMenuPresenter {
    static let shared = SegmentMenuPresenter()

    private var anchor: SegmentAnchorButton?

    func present(_ menu: UIMenu, under column: CGRect) {
        guard #available(iOS 17.4, *),
              let window = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .flatMap(\.windows)
                  .first(where: \.isKeyWindow) else { return }
        let host = window.rootViewController?.view ?? window
        let button = SegmentAnchorButton(type: .custom)
        button.backgroundColor = .clear
        button.showsMenuAsPrimaryAction = true
        button.preferredMenuElementOrder = .fixed
        let drop: CGFloat = 8
        anchor?.removeFromSuperview()
        button.frame = host.convert(CGRect(x: column.minX, y: column.maxY + drop,
                                           width: column.width, height: 1),
                                    from: window)
        host.addSubview(button)
        anchor = button
        button.menu = menu
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        button.performPrimaryAction()
    }

    static func segment(at x: CGFloat, in frame: CGRect, count: Int) -> Int? {
        guard count > 0, frame.width > 0, x >= frame.minX, x <= frame.maxX else { return nil }
        let width = frame.width / CGFloat(count)
        let index = Int((x - frame.minX) / width)
        return min(max(index, 0), count - 1)
    }

    static func column(_ index: Int, in frame: CGRect, count: Int) -> CGRect {
        guard count > 0 else { return frame }
        let width = frame.width / CGFloat(count)
        return CGRect(x: frame.minX + width * CGFloat(index), y: frame.minY,
                      width: width, height: frame.height)
    }

    static func anchor(at x: CGFloat, in frame: CGRect) -> CGRect {
        let side: CGFloat = 44
        let centre = min(max(x, frame.minX + side / 2), frame.maxX - side / 2)
        return CGRect(x: centre - side / 2, y: frame.minY,
                      width: side, height: frame.height)
    }
}

private final class SegmentAnchorButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
}

/// The gesture half
private struct SegmentLongPressMenu: ViewModifier {
    let count: Int
    /// Which strip this is, for the probe below
    let probeName: String
    let menu: (Int) -> UIMenu?

    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .background(SegmentHoldTarget(count: count, menu: menu))
            #if DEBUG
            .task {
                guard let raw = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_SEGMENT_MENU"]
                else { return }
                try? await Task.sleep(for: .milliseconds(1200))
                for field in raw.split(separator: ",") {
                    let parts = field.split(separator: ":")
                    guard parts.count == 2, parts[0] == probeName,
                          let index = Int(parts[1]), index < count,
                          let menu = menu(index) else { continue }
                    SegmentMenuPresenter.shared.present(
                        menu, under: SegmentMenuPresenter.column(index, in: frame, count: count))
                    try? await Task.sleep(for: .milliseconds(1500))
                }
            }
            #endif
    }
}

private struct SegmentHoldTarget: UIViewRepresentable {
    let count: Int
    let menu: (Int) -> UIMenu?

    func makeUIView(context: Context) -> SegmentHoldFinder {
        let view = SegmentHoldFinder()
        view.isUserInteractionEnabled = false
        view.count = count
        view.menu = menu
        return view
    }

    func updateUIView(_ view: SegmentHoldFinder, context: Context) {
        view.count = count
        view.menu = menu
        view.install()
    }
}

/// The view that goes looking
private final class SegmentHoldFinder: UIView {
    var count: Int = 0 { didSet { presenter?.count = count } }
    var menu: ((Int) -> UIMenu?)? {
        didSet { if let menu { presenter?.menu = menu } }
    }

    private weak var presenter: SegmentHoldPresenter?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        install()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        install()
    }

    func install() {
        guard let control = segmentedControl(), let menu else { return }
        if let existing = SegmentHoldPresenter.installed(on: control) {
            existing.count = count
            existing.menu = menu
            presenter = existing
            return
        }
        let presenter = SegmentHoldPresenter(count: count, menu: menu)
        presenter.attach(to: control)
        self.presenter = presenter
    }

    private func segmentedControl() -> UISegmentedControl? {
        var ancestor: UIView? = superview
        var climbed = 0
        while let view = ancestor, climbed < 6 {
            if let found = Self.firstControl(in: view) { return found }
            ancestor = view.superview
            climbed += 1
        }
        return nil
    }

    private static func firstControl(in root: UIView) -> UISegmentedControl? {
        var queue: [UIView] = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let control = view as? UISegmentedControl { return control }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }
}

/// Holds the control's hold
@MainActor
private final class SegmentHoldPresenter: NSObject, UIGestureRecognizerDelegate {
    private enum Key { nonisolated(unsafe) static var presenter: UInt8 = 0 }

    var count: Int
    var menu: (Int) -> UIMenu?

    init(count: Int, menu: @escaping (Int) -> UIMenu?) {
        self.count = count
        self.menu = menu
    }

    static func installed(on control: UISegmentedControl) -> SegmentHoldPresenter? {
        objc_getAssociatedObject(control, &Key.presenter) as? SegmentHoldPresenter
    }

    func attach(to control: UISegmentedControl) {
        objc_setAssociatedObject(control, &Key.presenter, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held))
        hold.minimumPressDuration = 0.4
        hold.cancelsTouchesInView = false
        hold.delaysTouchesBegan = false
        hold.delegate = self
        control.addGestureRecognizer(hold)
    }

    /// Alongside the control's own tracking, never instead of it
    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let control = gesture.view,
              let window = control.window else { return }
        let point = gesture.location(in: window)
        let frame = control.convert(control.bounds, to: window)
        guard let index = SegmentMenuPresenter.segment(at: point.x, in: frame, count: count),
              let menu = menu(index) else { return }
        SegmentMenuPresenter.shared.present(
            menu, under: SegmentMenuPresenter.anchor(at: point.x, in: frame))
    }
}

extension View {
    /// Gives a `Picker(.segmented)` a per-segment hold menu
    func segmentMenus(count: Int, probe: String,
                      menu: @escaping (Int) -> UIMenu?) -> some View {
        modifier(SegmentLongPressMenu(count: count, probeName: probe, menu: menu))
    }
}
#endif
