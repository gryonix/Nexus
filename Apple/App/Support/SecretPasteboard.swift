import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum SecretPasteboard {
    static let lifetime: TimeInterval = 90

    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.setItems(
            [["public.utf8-plain-text": string]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(lifetime)])
        #else
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let marker = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) {
            guard NSPasteboard.general.changeCount == marker else { return }
            NSPasteboard.general.clearContents()
        }
        #endif
    }
}
