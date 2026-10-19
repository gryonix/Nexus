import SwiftUI
import WidgetKit

/// Everything this app puts outside its own window
@main
struct gryonixNexusWidgetBundle: WidgetBundle {
    var body: some Widget {
        VPNStatusWidget()
        DevicesWidget()
        ServerMetricsWidget()
        FleetHealthWidget()
        SecurityWidget()
        BackupsWidget()
        UpdatesWidget()
        controls
        #if os(iOS)
        VPNLiveActivity()
        OperationLiveActivity()
        #endif
    }

    @WidgetBundleBuilder
    private var controls: some Widget {
        if #available(iOS 18.0, macOS 26.0, *) {
            VPNControlWidget()
        }
    }
}
