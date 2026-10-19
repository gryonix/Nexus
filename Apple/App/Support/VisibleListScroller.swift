#if os(iOS)
import UIKit

/// Scrolls the list the user is looking at
@MainActor
enum VisibleListScroller {
    static func scrollToEnd() {
        guard let window = keyWindow, let list = frontList(in: window) else { return }
        let bottom = list.contentSize.height + list.adjustedContentInset.bottom - list.bounds.height
        let top = -list.adjustedContentInset.top
        list.setContentOffset(CGPoint(x: list.contentOffset.x, y: max(bottom, top)), animated: true)
    }

    static func scrollToTop() {
        guard let window = keyWindow, let list = frontList(in: window) else { return }
        list.setContentOffset(CGPoint(x: list.contentOffset.x, y: -list.adjustedContentInset.top), animated: true)
    }

    /// Moves the visible list by a distance, within its bounds
    static func scroll(by distance: CGFloat, animated: Bool = true) {
        guard let window = keyWindow, let list = frontList(in: window) else { return }
        let top = -list.adjustedContentInset.top
        let bottom = list.contentSize.height + list.adjustedContentInset.bottom - list.bounds.height
        let target = min(max(list.contentOffset.y + distance, top), max(bottom, top))
        list.setContentOffset(CGPoint(x: list.contentOffset.x, y: target), animated: animated)
    }

    /// The list cards under a window rect, whole cells only
    static func cardFrames(around rect: CGRect, maxHeight: CGFloat) -> [CGRect] {
        guard let window = keyWindow,
              let list = frontList(in: window) as? UICollectionView else { return [] }
        let frames: [CGRect] = list.visibleCells.map { $0.convert($0.bounds, to: window) }
        var cards: [CGRect] = []
        for cell in frames.filter({ overlaps($0, rect) }).sorted(by: { $0.minY < $1.minY }) {
            if let first = cards.first, cell.maxY - first.minY > maxHeight { break }
            if let last = cards.last, cell.minY - last.maxY < 2 {
                cards[cards.count - 1] = last.union(cell)
            } else {
                cards.append(cell)
            }
        }
        return cards
    }

    private static func overlaps(_ cell: CGRect, _ rect: CGRect) -> Bool {
        let rows = cell.minY < rect.maxY - 2 && cell.maxY > rect.minY + 2
        return rows && cell.minX <= rect.midX && cell.maxX >= rect.midX
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private static func frontList(in window: UIWindow) -> UIScrollView? {
        let center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        return lists(in: window)
            .filter { isShown($0) && $0.convert($0.bounds, to: window).contains(center) }
            .max { $0.bounds.height * $0.bounds.width < $1.bounds.height * $1.bounds.width }
    }

    private static func lists(in view: UIView) -> [UIScrollView] {
        let own = (view as? UICollectionView).map { [$0 as UIScrollView] } ?? []
        return own + view.subviews.flatMap(lists(in:))
    }

    private static func isShown(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let node = current {
            if node.isHidden || node.alpha < 0.01 || node.layer.opacity < 0.01 { return false }
            current = node.superview
        }
        return view.window != nil
    }
}
#endif
