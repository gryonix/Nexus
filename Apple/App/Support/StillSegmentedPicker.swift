#if os(iOS) || os(tvOS)
import SwiftUI
import UIKit

/// A system segmented control whose pictures never fly in
struct StillSegmentedPicker: UIViewRepresentable {
    struct Item: Equatable {
        let id: String
        let title: String
        /// SF Symbol or asset name; nil shows the title
        var imageName: String?
    }

    let items: [Item]
    @Binding var selection: String

    func makeUIView(context: Context) -> StillSegmentedControl {
        let control = StillSegmentedControl(frame: .zero)
        control.onSelect = { selection = $0 }
        return control
    }

    func updateUIView(_ control: StillSegmentedControl, context: Context) {
        control.onSelect = { selection = $0 }
        control.apply(items, selected: selection)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: StillSegmentedControl,
                      context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width,
               height: proposal.height ?? uiView.intrinsicContentSize.height)
    }
}

final class StillSegmentedControl: UISegmentedControl {
    var onSelect: ((String) -> Void)?
    private var shown: [StillSegmentedPicker.Item] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(changed), for: .valueChanged)
        let font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .medium))
        let bold = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
        setTitleTextAttributes([.font: font], for: .normal)
        setTitleTextAttributes([.font: bold], for: .selected)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    /// Touches only what changed, never animated
    func apply(_ items: [StillSegmentedPicker.Item], selected: String) {
        if items != shown {
            UIView.performWithoutAnimation {
                if items.map(\.id) != shown.map(\.id) {
                    removeAllSegments()
                    for (index, item) in items.enumerated() { insertSegment(item, at: index) }
                } else {
                    for (index, item) in items.enumerated() where item != shown[index] {
                        setContent(item, at: index)
                    }
                }
                layoutIfNeeded()
            }
            shown = items
        }
        let index = items.firstIndex { $0.id == selected } ?? UISegmentedControl.noSegment
        if selectedSegmentIndex != index { selectedSegmentIndex = index }
    }

    private func insertSegment(_ item: StillSegmentedPicker.Item, at index: Int) {
        if let image = Self.image(for: item) {
            insertSegment(with: image, at: index, animated: false)
        } else {
            insertSegment(withTitle: item.title, at: index, animated: false)
        }
    }

    private func setContent(_ item: StillSegmentedPicker.Item, at index: Int) {
        if let image = Self.image(for: item) {
            setImage(image, forSegmentAt: index)
        } else {
            setTitle(item.title, forSegmentAt: index)
        }
    }

    /// One image per name, so unchanged pictures stay put
    private static var images: [String: UIImage] = [:]

    private static func image(for item: StillSegmentedPicker.Item) -> UIImage? {
        guard let name = item.imageName else { return nil }
        let image = images[name] ?? {
            let found = UIImage(systemName: name, withConfiguration: symbolSize) ?? asset(name)
            images[name] = found
            return found
        }()
        let labelled = image?.copy() as? UIImage
        labelled?.accessibilityLabel = item.title
        return labelled ?? image
    }

    private static let symbolSize = UIImage.SymbolConfiguration(
        pointSize: UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 17), weight: .regular)

    /// An asset drawn at the symbols' height, as a template
    private static func asset(_ name: String) -> UIImage? {
        guard let source = UIImage(named: name), source.size.height > 0 else { return nil }
        let side = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 21)
        let size = CGSize(width: side * source.size.width / source.size.height, height: side)
        return UIGraphicsImageRenderer(size: size).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }.withRenderingMode(.alwaysTemplate)
    }

    @objc private func changed() {
        guard shown.indices.contains(selectedSegmentIndex) else { return }
        onSelect?(shown[selectedSegmentIndex].id)
    }
}
#endif
