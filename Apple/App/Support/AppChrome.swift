import Foundation
import SwiftUI

enum AppChrome {
    static let classicKey = "appearance.classicChrome"

    /// Whether the app's own surfaces draw glass right now
    static var usesGlass: Bool {
        guard #available(iOS 26.0, macOS 26.0, *) else { return false }
        return !isClassic
    }

    static var isClassic: Bool {
        UserDefaults.standard.bool(forKey: classicKey)
    }

    static var isChoosable: Bool {
        if #available(iOS 26.0, macOS 26.0, *) { return true }
        return false
    }

    static var identity: String { usesGlass ? "glass" : "classic" }
}
