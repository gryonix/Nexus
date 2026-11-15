#if os(iOS) || os(tvOS)
import SwiftUI
import UIKit

/// Whether this device has a Dynamic Island and Live Activities
enum DynamicIsland {
    static var isOnThisDevice: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    /// What settings call the cards on this device
    static var settingsTitle: LocalizedStringKey {
        isOnThisDevice ? "Live Activity & Dynamic Island" : "Live Activity"
    }
}
#endif
