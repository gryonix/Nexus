import ServerControl
import SwiftUI

/// All, on the server, or on drives
struct BackupPlacePicker: View {
    @Binding var place: BackupFilter.Place

    var body: some View {
        Picker("Backups", selection: $place) {
            Text("All").tag(BackupFilter.Place.any)
            Text("On servers").tag(BackupFilter.Place.server)
            Text("On drives").tag(BackupFilter.Place.drives)
        }
        .pickerStyle(.segmented)
    }
}
