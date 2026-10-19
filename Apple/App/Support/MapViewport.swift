import CoreGraphics

/// What part of the map is on screen
struct MapViewport: Equatable {
    static let maxScale: CGFloat = 12

    let content: CGSize
    /// 1 fits the whole map into the view
    private(set) var scale: CGFloat = 1
    private(set) var origin: CGPoint = .zero

    var isZoomedIn: Bool { scale > 1.0001 }

    /// View points per map unit
    func pointsPerUnit(in view: CGSize) -> CGFloat {
        guard content.width > 0, content.height > 0, view.width > 0, view.height > 0 else { return 0 }
        return min(view.width / content.width, view.height / content.height) * scale
    }

    func visible(in view: CGSize) -> CGRect {
        let perUnit = pointsPerUnit(in: view)
        guard perUnit > 0 else { return CGRect(origin: origin, size: content) }
        let size = CGSize(width: view.width / perUnit, height: view.height / perUnit)
        return CGRect(origin: resolvedOrigin(size: size), size: size)
    }

    mutating func reset(in view: CGSize) {
        scale = 1
        origin = .zero
        clamp(in: view)
    }

    /// Keeps the map point under `anchor` where it is
    mutating func zoom(by factor: CGFloat, around anchor: CGPoint, in view: CGSize) {
        let before = mapPoint(for: anchor, in: view)
        scale = min(max(scale * factor, 1), Self.maxScale)
        let after = mapPoint(for: anchor, in: view)
        origin.x += before.x - after.x
        origin.y += before.y - after.y
        clamp(in: view)
    }

    /// Moves the map with the finger
    mutating func pan(by translation: CGSize, in view: CGSize) {
        let perUnit = pointsPerUnit(in: view)
        guard perUnit > 0 else { return }
        origin.x -= translation.width / perUnit
        origin.y -= translation.height / perUnit
        clamp(in: view)
    }

    func mapPoint(for viewPoint: CGPoint, in view: CGSize) -> CGPoint {
        let perUnit = pointsPerUnit(in: view)
        guard perUnit > 0 else { return origin }
        let corner = visible(in: view).origin
        return CGPoint(x: corner.x + viewPoint.x / perUnit, y: corner.y + viewPoint.y / perUnit)
    }

    private mutating func clamp(in view: CGSize) {
        origin = visible(in: view).origin
    }

    /// Inside the map, or centred when the map is smaller
    private func resolvedOrigin(size: CGSize) -> CGPoint {
        CGPoint(x: Self.clamped(origin.x, visible: size.width, content: content.width),
                y: Self.clamped(origin.y, visible: size.height, content: content.height))
    }

    private static func clamped(_ value: CGFloat, visible: CGFloat, content: CGFloat) -> CGFloat {
        let slack = content - visible
        return slack <= 0 ? slack / 2 : min(max(value, 0), slack)
    }
}
