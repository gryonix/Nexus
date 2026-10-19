import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The symbol a paired device is drawn with
enum PairedDeviceIcon {
    /// A label nothing recognises is a machine somebody named
    static let unknown = "desktopcomputer"

    /// What this app is running on
    @MainActor static var thisDevice: String {
        #if os(macOS)
        return "desktopcomputer"
        #elseif canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #else
        return unknown
        #endif
    }

    private static let families: [(symbol: String, words: [String])] = [
        ("applewatch", ["apple watch", "watch"]),
        ("appletv", ["apple tv"]),
        ("visionpro", ["vision pro", "apple vision"]),
        ("ipad", ["ipad"]),
        ("ipodtouch", ["ipod"]),
        ("iphone", ["iphone"]),
        ("laptopcomputer", ["macbook"]),
        ("desktopcomputer", ["imac", "mac mini", "mac studio", "mac pro", "macintosh", "mac"]),
        ("ipad", ["tab ", "tablet"]),
        ("smartphone", ["pixel", "galaxy", "samsung", "sm-", "xiaomi", "redmi", "poco",
                        "oneplus", "huawei", "honor", "oppo", "vivo", "realme", "motorola",
                        "moto ", "nokia", "zte", "tecno", "infinix", "nothing phone",
                        "android", "phone"]),
        ("pc", ["thinkpad", "surface", "windows", "desktop", "laptop", "linux", "ubuntu", "pc"])
    ]

    /// Phone, tablet, laptop or desktop, by the label
    static func symbol(for label: String) -> String {
        let text = label.lowercased()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return unknown }
        for family in families where family.words.contains(where: text.contains) {
            return family.symbol
        }
        return unknown
    }
}
