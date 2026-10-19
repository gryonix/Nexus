#if os(iOS)
import UIKit

final class SectionLensView: UIView {
    /// The unselected row
    let contentView = UIView()

    /// The selected row, inside the glass
    let liftedContentView = UIView()

    private let glass: UIVisualEffectView

    /// Holds the capsule
    let shadowHolder = UIView()

    private let lensClip = UIView()

    private static var slowMotion: Double {
        #if DEBUG
        Double(ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_SLOW_LENS"] ?? "") ?? 1
        #else
        1
        #endif
    }

    /// True where the system draws real glass
    let isGlass: Bool

    private var appliedSelection: CGRect?

    override init(frame: CGRect) {
        if #available(iOS 26.0, *), AppChrome.usesGlass {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = false
            effect.tintColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(white: 0, alpha: 0.22)
                    : UIColor(white: 1, alpha: 0.5)
            }
            glass = UIVisualEffectView(effect: effect)
            isGlass = true
        } else {
            glass = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            isGlass = false
        }
        super.init(frame: frame)

        addSubview(contentView)
        addSubview(shadowHolder)
        shadowHolder.addSubview(glass)
        lensClip.clipsToBounds = true
        lensClip.isUserInteractionEnabled = false
        lensClip.layer.cornerCurve = .continuous
        shadowHolder.addSubview(lensClip)
        lensClip.addSubview(liftedContentView)
        glass.isUserInteractionEnabled = false
        glass.clipsToBounds = true
        glass.layer.cornerCurve = .continuous
        shadowHolder.isUserInteractionEnabled = false
        contentView.isUserInteractionEnabled = false
        liftedContentView.isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    // MARK: - Layout

    /// Place the glass over `selection`, in this view's own coordinates
    func update(selection: CGRect, inset: CGVector, animated: Bool,
                onArrival: (() -> Void)? = nil) {
        contentView.frame = bounds
        let resting = selection.insetBy(dx: inset.dx, dy: inset.dy)
        guard resting.width > 0, resting.height > 0 else { onArrival?(); return }
        guard appliedSelection != resting else { onArrival?(); return }
        appliedSelection = resting

        guard animated else {
            place(resting)
            onArrival?()
            return
        }
        let duration = 0.6 * Self.slowMotion
        let airborne = resting.insetBy(dx: -Self.liftInset, dy: -Self.liftInset)
        UIView.animateKeyframes(withDuration: duration, delay: 0,
                                options: [.calculationModeCubic, .allowUserInteraction,
                                          .beginFromCurrentState]) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.45) {
                self.place(airborne, airborne: true)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.45, relativeDuration: 0.55) {
                self.place(resting, airborne: false)
            }
        } completion: { _ in onArrival?() }
    }

    private static let liftInset: CGFloat = 14

    func beginDrag(over rect: CGRect) {
        appliedSelection = nil
        UIView.animate(withDuration: 0.6 * 0.45 * Self.slowMotion, delay: 0,
                       options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
            self.place(rect.insetBy(dx: -Self.liftInset, dy: -Self.liftInset), airborne: true)
        }
    }

    /// The finger moved: the enlarged capsule tracks it
    func dragMove(to rect: CGRect) {
        appliedSelection = nil
        UIView.animate(withDuration: 0.09, delay: 0,
                       options: [.curveLinear, .allowUserInteraction, .beginFromCurrentState]) {
            self.place(rect.insetBy(dx: -Self.liftInset, dy: -Self.liftInset), airborne: true)
        }
    }

    func settle(onto rect: CGRect, inset: CGVector, onArrival: (() -> Void)? = nil) {
        let resting = rect.insetBy(dx: inset.dx, dy: inset.dy)
        appliedSelection = resting
        UIView.animate(withDuration: 0.6 * 0.55 * Self.slowMotion, delay: 0,
                       options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]) {
            self.place(resting, airborne: false)
        } completion: { _ in onArrival?() }
    }

    /// Put the capsule on `rect`
    private func place(_ rect: CGRect, airborne: Bool = false) {
        shadowHolder.frame = rect
        shadowHolder.layer.shadowColor = UIColor.black.cgColor
        shadowHolder.layer.shadowOffset = CGSize(width: 0, height: 3)
        shadowHolder.layer.shadowRadius = 10
        shadowHolder.layer.shadowOpacity = airborne ? 0.28 : 0
        shadowHolder.layer.shadowPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: rect.size),
                                                     cornerRadius: rect.height / 2).cgPath
        glass.frame = CGRect(origin: .zero, size: rect.size)
        glass.layer.cornerRadius = rect.height / 2
        lensClip.frame = CGRect(origin: .zero, size: rect.size)
        lensClip.layer.cornerRadius = rect.height / 2
        let row = bounds
        liftedContentView.bounds = CGRect(origin: .zero, size: row.size)
        liftedContentView.transform = .identity
        liftedContentView.center = CGPoint(x: row.width / 2 - rect.minX,
                                           y: row.height / 2 - rect.minY)
    }
}

final class GlassPanelView: UIView {
    private let effectView: UIVisualEffectView

    var panelContent: UIView { effectView.contentView }

    override init(frame: CGRect) {
        if #available(iOS 26.0, *), AppChrome.usesGlass {
            let glass = UIGlassEffect(style: .regular)
            glass.isInteractive = false
            glass.tintColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(white: 1, alpha: 0.025)
                    : UIColor(white: 1, alpha: 0.1)
            }
            effectView = UIVisualEffectView(effect: glass)
        } else {
            effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        }
        super.init(frame: frame)
        addSubview(effectView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    func corner(_ radius: CGFloat) {
        effectView.frame = bounds
        effectView.contentView.frame = effectView.bounds
        effectView.layer.cornerRadius = radius
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true
    }
}
#endif
