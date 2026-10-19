#if os(iOS)
import SwiftUI
import UIKit

struct GlassSegmentStrip: UIViewRepresentable {
    let items: [StripItem]
    @Binding var selection: String
    let identifier: String
    /// What `GRYONIXNEXUS_DEMO_SEGMENT_MENU=<probe>:<index>` calls it
    let probe: String
    let menu: (String) -> UIMenu?
    /// Tapped the item that is ALREADY selected
    var onReselect: ((String) -> Void)?
    var hugsContent = false
    var tabBarStyle = false
    /// The colour the selected section is painted in, for `tabBarStyle`
    var selectedTint: Color?
    var dragToSwitch = false

    func makeUIView(context: Context) -> SegmentStripView {
        let strip = SegmentStripView()
        strip.hugsContent = hugsContent
        strip.tabBarStyle = tabBarStyle
        strip.dragToSwitch = dragToSwitch
        strip.selectedTint = selectedTint.map(UIColor.init)
        strip.onSelect = { id in
            selection = id
        }
        strip.onReselect = { onReselect?($0) }
        strip.menu = { menu($0) }
        strip.accessibilityIdentifier = identifier
        strip.probeName = probe
        return strip
    }

    func updateUIView(_ strip: SegmentStripView, context: Context) {
        strip.hugsContent = hugsContent
        strip.tabBarStyle = tabBarStyle
        strip.dragToSwitch = dragToSwitch
        strip.selectedTint = selectedTint.map(UIColor.init)
        strip.apply(items: items, selection: selection)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SegmentStripView,
                      context: Context) -> CGSize? {
        let offered = proposal.width ?? UIView.layoutFittingExpandedSize.width
        let hugs = hugsContent || tabBarStyle
        let width = hugs ? min(uiView.naturalContentWidth, offered) : offered
        return CGSize(width: width, height: uiView.preferredHeight)
    }
}

struct StripItem: Equatable {
    let id: String
    let title: String
    let identifier: String
    var iconName: String?
}

/// The strip itself
final class SegmentStripView: UIView {
    /// What `GRYONIXNEXUS_DEMO_SEGMENT_MENU` calls this strip
    var probeName = "sections"

    /// Content-width instead of full-width — see `GlassSegmentStrip.hugsContent`
    var hugsContent = false
    /// Tab-bar drawing: stacked icon, system height, small label — see `GlassSegmentStrip.tabBarStyle`
    var tabBarStyle = false
    /// Drag along the strip to switch — see `GlassSegmentStrip.dragToSwitch`
    var dragToSwitch = false
    /// The selected section's colour for `tabBarStyle` — see `GlassSegmentStrip.selectedTint`
    var selectedTint: UIColor? {
        didSet {
            guard selectedTint != oldValue, !items.isEmpty else { return }
            applyFonts()
        }
    }

    var naturalContentWidth: CGFloat {
        items.map { widthOfSection(of: $0) }.reduce(0, +) + Self.inset * 2
    }

    var onSelect: ((String) -> Void)?
    var onReselect: ((String) -> Void)?
    var menu: ((String) -> UIMenu?)?

    // MARK: - The numbers

    private static let inset: CGFloat = 4
    private static let capsuleInset: CGFloat = 1

    /// The resting capsule's inset from its section box
    private var restingInset: CGVector {
        CGVector(dx: Self.capsuleInset, dy: tabBarStyle ? 0 : Self.capsuleInset)
    }
    private var labelPadding: CGFloat { tabBarStyle ? 9 : 14 }
    private static let baseHeight: CGFloat = 44
    private static let baseLabelSize: CGFloat = 15
    private static let travel: TimeInterval = 0.5

    /// `baseHeight` covers the per-server strips
    private static let tabBarHeight: CGFloat = 62

    var preferredHeight: CGFloat {
        UIFontMetrics(forTextStyle: .subheadline)
            .scaledValue(for: tabBarStyle ? Self.tabBarHeight : Self.baseHeight)
    }

    private var stacksIcon: Bool { tabBarStyle }
    private var labelSize: CGFloat { tabBarStyle ? 10 : Self.baseLabelSize }

    private var restColor: UIColor { tabBarStyle ? .label : .secondaryLabel }

    /// The colour of the section UNDER the lens
    private var selectedColor: UIColor { tabBarStyle ? (selectedTint ?? tintColor) : .label }

    private var labelFont: UIFont {
        UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: labelSize, weight: .medium))
    }

    private var inkFont: UIFont {
        UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: labelSize, weight: .semibold))
    }

    // MARK: - The pieces

    private let track = GlassPanelView()
    private let scrollView = UIScrollView()
    private let lens = SectionLensView()
    private let flightLayer = UIView()
    private let flightClip = UIView()

    private var items: [StripItem] = []
    private var selection: String?
    /// Set in `layoutSubviews` — `tabBarStyle` and everything on screen
    private var dragSwitchesSections = false
    private var isDragging = false
    /// The section the finger is currently over during a drag
    private var dragPreview: String?
    /// Which section reads as chosen right now
    private var shownSelection: String? { dragPreview ?? selection }
    private var greyLabels: [String: UILabel] = [:]
    private var inkLabels: [String: UILabel] = [:]
    private var itemFrames: [String: CGRect] = [:]
    private var hasLaidOut = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(track)

        scrollView.clipsToBounds = true
        scrollView.layer.cornerCurve = .continuous
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)
        scrollView.addSubview(lens)
        flightLayer.isUserInteractionEnabled = false
        flightClip.isUserInteractionEnabled = false
        addSubview(flightClip)
        flightClip.addSubview(flightLayer)
        flightLayer.addSubview(lens.shadowHolder)
        scrollView.delegate = self

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold))
        hold.minimumPressDuration = 0.45
        scrollView.addGestureRecognizer(hold)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.require(toFail: hold)
        scrollView.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.require(toFail: hold)
        pan.delegate = self
        scrollView.addGestureRecognizer(pan)

        shouldGroupAccessibilityChildren = true

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.applyFonts()
            self.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    // MARK: - What SwiftUI hands down

    func apply(items: [StripItem], selection: String) {
        let sectionsChanged = items != self.items
        let selectionChanged = selection != self.selection
        self.items = items
        self.selection = selection

        if sectionsChanged { rebuildLabels() }
        if sectionsChanged || selectionChanged {
            updateSelectedTraits()
            applyFonts()
            setNeedsLayout()
            if selectionChanged && hasLaidOut && !sectionsChanged {
                layoutIfNeeded()
                revealSelection(animated: true)
            }
        }
    }

    /// One label per section in each row, laid out identically
    private func rebuildLabels() {
        for label in greyLabels.values { label.removeFromSuperview() }
        for label in inkLabels.values { label.removeFromSuperview() }
        greyLabels = [:]
        inkLabels = [:]

        for item in items {
            let grey = UILabel()
            grey.attributedText = rowText(item, tint: restColor, font: labelFont)
            grey.numberOfLines = stacksIcon ? 2 : 1
            grey.textAlignment = .center
            grey.textColor = restColor
            grey.lineBreakMode = .byClipping
            grey.isAccessibilityElement = true
            grey.accessibilityLabel = item.title
            grey.accessibilityIdentifier = item.identifier
            lens.contentView.addSubview(grey)
            greyLabels[item.id] = grey

            let ink = UILabel()
            ink.attributedText = rowText(item, tint: selectedColor, font: inkFont)
            ink.numberOfLines = stacksIcon ? 2 : 1
            ink.textAlignment = .center
            ink.textColor = selectedColor
            ink.lineBreakMode = .byClipping
            ink.isAccessibilityElement = false
            ink.accessibilityElementsHidden = true
            lens.liftedContentView.addSubview(ink)
            inkLabels[item.id] = ink
        }
        applyFonts()
        updateSelectedTraits()
    }

    private func applyFonts() {
        for item in items {
            greyLabels[item.id]?.attributedText = rowText(item, tint: restColor, font: labelFont)
            greyLabels[item.id]?.textColor = restColor
            inkLabels[item.id]?.attributedText = rowText(item, tint: selectedColor, font: inkFont)
            inkLabels[item.id]?.textColor = selectedColor
        }
        syncGreyForLens(travelling: false)
    }

    private func syncGreyForLens(travelling: Bool) {
        for (id, label) in greyLabels {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            let hidden = !travelling && id == shownSelection
            label.attributedText = rowText(item, tint: hidden ? .clear : restColor,
                                           font: labelFont)
        }
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        if tabBarStyle { applyFonts() }
    }

    private func rowText(_ item: StripItem, tint: UIColor, font: UIFont) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: item.title,
            attributes: [.font: font, .foregroundColor: tint])
        guard let name = item.iconName else { return text }
        let pointSize = stacksIcon
            ? UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 24)
            : font.pointSize
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let base = UIImage(systemName: name)?.applyingSymbolConfiguration(config)
            ?? UIImage(named: name)?.applyingSymbolConfiguration(config)
            ?? UIImage(named: name)
        guard let image = base?.withTintColor(tint, renderingMode: .alwaysOriginal) else { return text }
        let attachment = NSTextAttachment()
        attachment.image = image
        let glyphHeight = min(image.size.height, pointSize * 1.15)
        attachment.bounds = CGRect(x: 0, y: stacksIcon ? -2 : font.descender * 0.6,
                                   width: image.size.width * (glyphHeight / max(image.size.height, 1)),
                                   height: glyphHeight)
        let run = NSMutableAttributedString(attachment: attachment)
        if stacksIcon {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineSpacing = 1
            run.append(NSAttributedString(string: "\n"))
            run.append(text)
            run.addAttribute(.paragraphStyle, value: paragraph,
                             range: NSRange(location: 0, length: run.length))
        } else {
            run.append(NSAttributedString(string: "\u{2009}\u{2009}"))
            run.append(text)
        }
        return run
    }

    /// Which section reads as chosen
    private func updateSelectedTraits() {
        for (id, label) in greyLabels {
            label.accessibilityTraits = id == selection ? [.button, .selected] : [.button]
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = bounds.height
        guard height > 0, !items.isEmpty else { return }

        track.frame = bounds
        track.corner(height / 2)
        scrollView.frame = bounds
        scrollView.layer.cornerRadius = height / 2
        scrollView.layer.mask = nil

        let rowHeight = height - Self.inset * 2
        let natural = items.map { widthOfSection(of: $0) }
        let naturalTotal = natural.reduce(0, +)
        let fills = naturalTotal + Self.inset * 2 <= bounds.width
        let columns = tabBarStyle || !fills ? nil
            : Self.filledColumns(natural: natural, available: bounds.width - Self.inset * 2)
        let contentWidth = fills ? bounds.width : naturalTotal + Self.inset * 2
        dragSwitchesSections = dragToSwitch && fills
        scrollView.isScrollEnabled = !fills

        lens.frame = CGRect(x: 0, y: 0, width: contentWidth, height: bounds.height)
        flightClip.frame = bounds
        flightLayer.frame = CGRect(x: -scrollView.contentOffset.x, y: 0,
                                   width: contentWidth, height: bounds.height)
        scrollView.contentSize = CGSize(width: contentWidth, height: bounds.height)
        maskFlightLayer()

        let leftover = tabBarStyle && fills ? max(0, bounds.width - Self.inset * 2 - naturalTotal) : 0
        var x = Self.inset + leftover / 2
        itemFrames = [:]
        for (index, item) in items.enumerated() {
            let width = columns?[index] ?? natural[index]
            let frame = CGRect(x: x, y: Self.inset, width: width, height: rowHeight)
            itemFrames[item.id] = frame
            greyLabels[item.id]?.frame = frame
            inkLabels[item.id]?.frame = frame
            x += width
        }

        revealSelection(animated: false)
        hasLaidOut = true
    }

    static func filledColumns(natural: [CGFloat], available: CGFloat) -> [CGFloat]? {
        if let equal = equalColumns(natural: natural, available: available) { return equal }
        guard !natural.isEmpty, available > 0 else { return nil }
        let total = natural.reduce(0, +)
        guard total > 0 else { return nil }
        let leftover = max(0, available - total)
        return natural.map { $0 + leftover * ($0 / total) }
    }

    static func equalColumns(natural: [CGFloat], available: CGFloat) -> [CGFloat]? {
        guard !natural.isEmpty, available > 0 else { return nil }
        let count = CGFloat(natural.count)
        let share = available / count
        guard natural.allSatisfy({ $0 <= share }) else { return nil }
        return (0..<natural.count).map { index in
            available * CGFloat(index + 1) / count - available * CGFloat(index) / count
        }
    }

    private static let liftMargin: CGFloat = 32

    private static var closesOver: CGFloat { inset + capsuleInset }

    static func flightRoom(bar: CGRect, contentWidth: CGFloat, offset: CGFloat) -> CGRect {
        let hidden = max(0, contentWidth - bar.width)
        let pastLeading = min(max(offset, 0), hidden)
        let pastTrailing = hidden - pastLeading
        let radius = bar.height / 2
        func edge(_ past: CGFloat) -> CGFloat {
            let open = max(0, closesOver - past) / closesOver
            return radius - (radius + liftMargin) * open
        }
        let leading = edge(pastLeading)
        let trailing = edge(pastTrailing)
        return CGRect(x: bar.minX + leading,
                      y: bar.minY - liftMargin,
                      width: max(0, bar.width - leading - trailing),
                      height: bar.height + liftMargin * 2)
    }

    private var appliedFlightRoom: CGRect?

    private func maskFlightLayer() {
        let bar = bounds
        guard bar.height > 0, bar.width > 0 else { return }
        let room = Self.flightRoom(bar: bar,
                                   contentWidth: scrollView.contentSize.width,
                                   offset: scrollView.contentOffset.x)
        let installed = flightClip.layer.mask as? CAShapeLayer
        guard installed == nil || room != appliedFlightRoom || installed?.frame != bar else { return }
        let mask = installed ?? CAShapeLayer()
        appliedFlightRoom = room
        let path = UIBezierPath(roundedRect: bar, cornerRadius: bar.height / 2)
        if room.width > 0 {
            path.append(UIBezierPath(roundedRect: room, cornerRadius: Self.liftMargin))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = bar
        mask.path = path.cgPath
        flightClip.layer.mask = mask
        CATransaction.commit()
    }

    private static let minimumTabWidth: CGFloat = 64

    private func widthOfSection(of item: StripItem) -> CGFloat {
        if stacksIcon {
            let label = (item.title as NSString)
                .size(withAttributes: [.font: inkFont]).width
            let icon: CGFloat = item.iconName == nil ? 0
                : UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 25)
            let content = ceil(max(label, icon)) + labelPadding * 2
            return max(content, Self.minimumTabWidth)
        }
        let width = rowText(item, tint: .label, font: inkFont).size().width
        return ceil(width) + labelPadding * 2
    }

    private func revealSelection(animated: Bool) {
        // The finger owns the capsule while a drag is running.
        guard !isDragging else { return }
        guard let selection, let frame = itemFrames[selection] else { return }
        let travels = animated && hasLaidOut
        if travels { syncGreyForLens(travelling: true) }
        lens.update(selection: frame, inset: restingInset,
                    animated: travels,
                    onArrival: { [weak self] in self?.syncGreyForLens(travelling: false) })
        let visible = frame.insetBy(dx: -Self.inset, dy: 0)
        guard scrollView.contentSize.width > scrollView.bounds.width else { return }
        guard animated, hasLaidOut else {
            return scrollView.scrollRectToVisible(visible, animated: false)
        }
        UIView.animate(withDuration: Self.travel, delay: 0,
                       options: [.curveEaseInOut, .allowUserInteraction]) {
            self.scrollView.scrollRectToVisible(visible, animated: false)
        }
    }

    // MARK: - What a touch does

    @objc private func handleTap(_ recogniser: UITapGestureRecognizer) {
        guard let id = section(at: recogniser.location(in: lens)) else { return }
        if id == selection {
            onReselect?(id)
            return
        }
        Haptics.play(.tap)
        selection = id
        updateSelectedTraits()
        revealSelection(animated: true)
        onSelect?(id)
    }

    @objc private func handlePan(_ recogniser: UIPanGestureRecognizer) {
        guard dragSwitchesSections else { return }
        let x = recogniser.location(in: lens).x

        func target() -> (id: String, box: CGRect)? {
            guard let id = section(at: CGPoint(x: x, y: lens.bounds.midY)) ?? nearestSection(toX: x),
                  let frame = itemFrames[id] else { return nil }
            let clampedX = min(max(x, frame.width / 2), lens.bounds.width - frame.width / 2)
            let box = CGRect(x: clampedX - frame.width / 2, y: frame.minY,
                             width: frame.width, height: frame.height)
            if id != dragPreview {
                Haptics.play(.tap)
                dragPreview = id
                applyFonts()
            }
            return (id, box)
        }

        switch recogniser.state {
        case .began:
            isDragging = true
            dragPreview = selection
            if let t = target() { lens.beginDrag(over: t.box) }

        case .changed:
            isDragging = true
            if let t = target() { lens.dragMove(to: t.box) }

        case .ended:
            isDragging = false
            let landed = dragPreview
            dragPreview = nil
            if let landed, landed != selection {
                selection = landed
                onSelect?(landed)
            }
            updateSelectedTraits()
            applyFonts()
            settleCapsule()

        case .cancelled, .failed:
            isDragging = false
            dragPreview = nil
            updateSelectedTraits()
            applyFonts()
            settleCapsule()

        default:
            break
        }
    }

    private func settleCapsule() {
        guard let selection, let frame = itemFrames[selection] else { return }
        lens.settle(onto: frame, inset: restingInset) { [weak self] in
            self?.syncGreyForLens(travelling: false)
        }
    }

    private func panShouldBegin() -> Bool { dragSwitchesSections }

    private func nearestSection(toX x: CGFloat) -> String? {
        items.map(\.id).min { a, b in
            abs((itemFrames[a]?.midX ?? .greatestFiniteMagnitude) - x)
                < abs((itemFrames[b]?.midX ?? .greatestFiniteMagnitude) - x)
        }
    }

    @objc private func handleHold(_ recogniser: UILongPressGestureRecognizer) {
        guard recogniser.state == .began,
              let id = section(at: recogniser.location(in: lens)) else { return }
        present(menuFor: id)
    }

    private func present(menuFor id: String) {
        guard let menu = menu?(id), let frame = itemFrames[id], window != nil else { return }
        let strip = convert(bounds, to: nil)
        let section = lens.convert(frame, to: nil)
        SegmentMenuPresenter.shared.present(
            menu, under: SegmentMenuPresenter.anchor(at: section.midX, in: strip))
    }

    /// Which section a point in the row belongs to
    private func section(at point: CGPoint) -> String? {
        items.map(\.id).first {
            itemFrames[$0]?.insetBy(dx: 0, dy: -Self.inset).contains(point) ?? false
        }
    }

    // MARK: - The screenshot probe

    #if DEBUG
    /// `GRYONIXNEXUS_DEMO_SEGMENT_MENU=sections:2` — the hold, opened without a finger
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !hasRunMenuProbe,
              let raw = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_SEGMENT_MENU"]
        else { return }
        hasRunMenuProbe = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            for field in raw.split(separator: ",") {
                let parts = field.split(separator: ":")
                guard parts.count == 2, parts[0] == probeName,
                      let index = Int(parts[1]), items.indices.contains(index) else { continue }
                present(menuFor: items[index].id)
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
    }

    private var hasRunMenuProbe = false
    #endif
}

extension SegmentStripView: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ recogniser: UIGestureRecognizer) -> Bool {
        if recogniser is UIPanGestureRecognizer, recogniser.view === scrollView {
            return panShouldBegin()
        }
        return super.gestureRecognizerShouldBegin(recogniser)
    }
}

extension SegmentStripView: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        flightLayer.frame.origin.x = -scrollView.contentOffset.x
        maskFlightLayer()
    }
}
#endif
