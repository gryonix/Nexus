import SwiftUI

struct CountryRegionPickerView: View {
    @Binding var codes: [String]

    @State private var search = ""
    @State private var fullScreenMap = false
    @AppStorage("countryPickerMapScrolls") private var mapScrolls = false

    var body: some View {
        let selected = Set(codes)
        Form {
            if mapScrolls {
                Section { mapCard(selected) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            continentsSection(selected)
            regionsSection(selected)
            countriesSection(selected)
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .safeAreaInset(edge: .top, spacing: 0) {
            if !mapScrolls {
                mapCard(selected)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .background(WorldMapView.pageBackground)
            }
        }
        .navigationTitle("Countries")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { moreMenu }
        #if os(iOS)
        .fullScreenCover(isPresented: $fullScreenMap) { fullScreen }
        #else
        .sheet(isPresented: $fullScreenMap) { fullScreen }
        #endif
        #if os(iOS)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search countries"))
        #else
        .searchable(text: $search, prompt: Text("Search countries"))
        #endif
    }

    private func mapCard(_ selected: Set<String>) -> some View {
        WorldMapView(selected: selected, onToggle: { toggle(code: $0) },
                     onExpand: { fullScreenMap = true })
            .padding(10)
            .background(WorldMapView.plate, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .animation(.snappy, value: mapScrolls)
    }

    private var fullScreen: some View {
        NavigationStack {
            ZStack {
                WorldMapView.plate.ignoresSafeArea()
                WorldMapView(selected: Set(codes), onToggle: { toggle(code: $0) },
                             fillsSpace: true)
                    .padding(10)
            }
                .navigationTitle("Countries")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { fullScreenMap = false }
                    }
                }
        }
    }

    private var moreMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Toggle(isOn: $mapScrolls) {
                    Label("Map scrolls with the list", systemImage: "map")
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }

    private func toggle(code: String) {
        var set = Set(codes)
        if set.contains(code) { set.remove(code) } else { set.insert(code) }
        codes = set.sorted()
    }

    // MARK: - Continents and regions

    @ViewBuilder
    private func continentsSection(_ selected: Set<String>) -> some View {
        Section {
            ForEach(Continent.allCases) { continent in
                groupRow(continent.displayName,
                         members: CountryCatalog.codes(in: continent), selected: selected)
            }
        } header: {
            InfoSectionHeader("Continents", note: "A continent ticks every region under it. The number on each row is how many of its countries are picked.")
        }
    }

    @ViewBuilder
    private func regionsSection(_ selected: Set<String>) -> some View {
        Section {
            ForEach(CountryRegion.allCases) { region in
                groupRow(region.displayName,
                         members: CountryCatalog.codes(in: region), selected: selected)
            }
        } header: {
            InfoSectionHeader("Regions", note: "Choose a whole region at once, or search for one country below.")
        }
    }

    private func groupRow(_ title: LocalizedStringKey, members: [String],
                          selected: Set<String>) -> some View {
        let selectedCount = members.filter(selected.contains).count
        return Button {
            toggle(members: members, currentlyAllSelected: selectedCount == members.count)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: "\(selectedCount)/\(members.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                groupMark(selectedCount: selectedCount, total: members.count)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func groupMark(selectedCount: Int, total: Int) -> some View {
        if selectedCount == total {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
        } else if selectedCount > 0 {
            Image(systemName: "minus.circle.fill").foregroundStyle(Color.secondary)
        } else {
            Image(systemName: "circle").foregroundStyle(Color.secondary)
        }
    }

    private func toggle(members: [String], currentlyAllSelected: Bool) {
        var set = Set(codes)
        if currentlyAllSelected {
            members.forEach { set.remove($0) }
        } else {
            members.forEach { set.insert($0) }
        }
        codes = set.sorted()
    }

    // MARK: - Countries

    @ViewBuilder
    private func countriesSection(_ selected: Set<String>) -> some View {
        Section {
            ForEach(filteredCountries, id: \.code) { entry in
                countryRow(entry.code, name: entry.name, selected: selected)
            }
            if filteredCountries.isEmpty {
                Text("No country matches this search.").foregroundStyle(.secondary)
            }
        } header: {
            InfoSectionHeader("Countries", note: "Blocking a country stops every address in it before it has tried anything; allowing only a few is the opposite order and refuses everywhere else, which is worth being sure about — your own phone abroad is somewhere else.")
        }
    }

    private func countryRow(_ code: String, name: String, selected: Set<String>) -> some View {
        Button {
            toggle(code: code)
        } label: {
            HStack {
                Text(verbatim: [CountryCatalog.flag(code), name].filter { !$0.isEmpty }.joined(separator: " "))
                Spacer()
                if selected.contains(code) {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filteredCountries: [(code: String, name: String)] {
        let all = CountryCatalog.allCodes
            .map { (code: $0, name: CountryCatalog.name(for: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.code.localizedCaseInsensitiveContains(query)
        }
    }
}
