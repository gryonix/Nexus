import SwiftUI

enum BrandMark {
    static let logo = "TabIconLogo"
    /// The bare globe: the same drawing with the shield open
    static let globe = "TabIconGlobe"

    /// The mark at a stated size
    static func vpn(size: CGFloat) -> some View {
        Image(logo)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }

    static func globeMark(size: CGFloat) -> some View {
        Image(globe)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }

    static var vpn: Image { Image(logo) }
}
