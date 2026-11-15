import ServerControlSSH
import SwiftUI

/// Picks how this device reaches the local machine
struct HomePathPicker: View {
    @Binding var selection: HomePathChoice

    var body: some View {
        WrappingPicker("Connect to the local machine", selection: $selection) {
            Text("Automatically").tag(HomePathChoice.automatic)
            Text("Through the VPS").tag(HomePathChoice.throughVPS)
            Text("Over the local network").tag(HomePathChoice.localNetwork)
        }
    }
}
