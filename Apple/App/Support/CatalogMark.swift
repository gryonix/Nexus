import ServiceCatalog
import SwiftUI

/// A catalog shelf's picture, as this app draws it
extension ServiceCategory {
    /// True for the one shelf whose picture this app owns
    var drawsBrandMark: Bool { id == ServiceCategory.vpn.id }
}

struct CategoryIcon: View {
    let category: ServiceCategory
    var size: CGFloat = 20

    var body: some View {
        if category.drawsBrandMark {
            BrandMark.vpn(size: size)
        } else {
            Image(systemName: category.systemImage)
        }
    }
}
