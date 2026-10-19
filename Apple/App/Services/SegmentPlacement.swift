import Foundation
import SwiftUI

protocol SegmentPlacement: RawRepresentable, Equatable where RawValue == String {
    var menuTitle: String { get }
}

extension SegmentPlacement {
    var title: LocalizedStringKey { LocalizedStringKey(menuTitle) }
}
