#if os(iOS)
import SwiftUI
import UIKit

struct DashboardSegmentStrip: View {
    let tabs: [DashboardTab]
    @Binding var selection: DashboardTab
    let menu: (DashboardTab) -> UIMenu?

    var body: some View {
        GlassSegmentStrip(
            items: tabs.map {
                StripItem(id: $0.rawValue, title: $0.localizedTitle,
                          identifier: "dashboard.section.\($0.rawValue)")
            },
            selection: Binding(get: { selection.rawValue },
                               set: { id in
                                   guard let tab = DashboardTab(rawValue: id) else { return }
                                   selection = tab
                               }),
            identifier: "dashboard.sections",
            probe: "sections",
            menu: { id in DashboardTab(rawValue: id).flatMap(menu) },
            dragToSwitch: true)
    }
}
#endif
