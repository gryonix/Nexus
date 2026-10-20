#if os(iOS)
import SwiftUI
import UIKit

/// The custom tab bar standing upright beside the content
struct SideTabRail: UIViewRepresentable {
    let tabs: [AppTab]
    @Binding var selection: AppTab
    let tunnelActive: Bool
    let selectedTint: Color
    let width: CGFloat
    let onReselect: (AppTab) -> Void

    static let gap: CGFloat = 10

    /// Fits the trailing column with a gap each side
    static func width(column: CGFloat) -> CGFloat {
        min(76, max(56, column - gap * 2))
    }

    /// Squarish phone screens put the bar at the side
    static func applies(to size: CGSize) -> Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone, size.width > 0 else { return false }
        return size.height / size.width < 1.7
    }

    func makeUIView(context: Context) -> SideRailView {
        SideRailView()
    }

    func updateUIView(_ rail: SideRailView, context: Context) {
        rail.selectedTint = UIColor(selectedTint)
        rail.onSelect = { tab in
            if tab == selection { onReselect(tab) } else { selection = tab }
        }
        rail.apply(tabs: tabs, selection: selection, tunnelActive: tunnelActive)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SideRailView,
                      context: Context) -> CGSize? {
        let offered = proposal.height ?? uiView.naturalHeight
        return CGSize(width: width, height: min(uiView.naturalHeight, offered))
    }
}

final class SideRailView: UIView {
    var selectedTint: UIColor = .tintColor
    var onSelect: (AppTab) -> Void = { _ in }

    private let track = GlassPanelView()
    private let scrollView = UIScrollView()
    private let highlight = UIView()
    private var buttons: [AppTab: UIButton] = [:]
    private var tabs: [AppTab] = []
    private var selection: AppTab?

    private static let itemHeight: CGFloat = 58
    private static let itemGap: CGFloat = 8
    private static let inset: CGFloat = 6

    var naturalHeight: CGFloat {
        let gaps = CGFloat(max(tabs.count - 1, 0)) * Self.itemGap
        return CGFloat(tabs.count) * Self.itemHeight + gaps + Self.inset * 2
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(track)
        scrollView.showsVerticalScrollIndicator = false
        track.panelContent.addSubview(scrollView)
        highlight.backgroundColor = .tertiarySystemFill
        highlight.layer.cornerCurve = .continuous
        scrollView.addSubview(highlight)
        accessibilityIdentifier = "shell.sections"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    func apply(tabs: [AppTab], selection: AppTab, tunnelActive: Bool) {
        if tabs != self.tabs { rebuild(tabs) }
        self.selection = selection
        for (tab, button) in buttons {
            button.configuration = configuration(for: tab, tunnelActive: tunnelActive,
                                                 selected: tab == selection)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.75
        }
        setNeedsLayout()
    }

    private func rebuild(_ tabs: [AppTab]) {
        buttons.values.forEach { $0.removeFromSuperview() }
        buttons = [:]
        self.tabs = tabs
        for tab in tabs {
            let button = UIButton(primaryAction: UIAction { [weak self] _ in self?.onSelect(tab) })
            button.menu = TabBarMenuPresenter.customBarMenu(for: tab)
            button.accessibilityIdentifier = "shell.section.\(tab.rawValue)"
            button.accessibilityLabel = UIL10n.string(tab.titleKey)
            scrollView.addSubview(button)
            buttons[tab] = button
        }
    }

    private func configuration(for tab: AppTab, tunnelActive: Bool,
                               selected: Bool) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        let name = tab.barIconName(tunnelActive: tunnelActive)
        let symbol = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
        config.image = (UIImage(systemName: name) ?? UIImage(named: name))?
            .applyingSymbolConfiguration(symbol)?
            .withRenderingMode(.alwaysTemplate)
        config.imagePlacement = .top
        config.imagePadding = 3
        var title = AttributeContainer()
        title.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        config.attributedTitle = AttributedString(UIL10n.string(tab.titleKey), attributes: title)
        config.titleLineBreakMode = .byClipping
        config.baseForegroundColor = selected ? selectedTint : .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 1, bottom: 4, trailing: 1)
        return config
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        track.frame = bounds
        track.corner(bounds.width / 2)
        scrollView.frame = bounds
        scrollView.contentSize = CGSize(width: bounds.width, height: naturalHeight)
        var y = Self.inset
        for tab in tabs {
            buttons[tab]?.frame = CGRect(x: Self.inset, y: y, width: bounds.width - Self.inset * 2,
                                         height: Self.itemHeight)
            y += Self.itemHeight + Self.itemGap
        }
        placeHighlight()
    }

    private func placeHighlight() {
        guard let selection, let frame = buttons[selection]?.frame else {
            highlight.isHidden = true
            return
        }
        highlight.isHidden = false
        highlight.frame = frame
        highlight.layer.cornerRadius = min(frame.width, frame.height) / 2
        scrollView.scrollRectToVisible(frame, animated: false)
    }
}
#endif
