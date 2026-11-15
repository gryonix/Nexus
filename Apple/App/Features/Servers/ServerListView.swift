import ServerControl
import ServiceCatalog
import SwiftUI
import UniformTypeIdentifiers

struct ServerListView: View {
    /// The glass strip's height, which the system picker matches
    @ScaledMetric(relativeTo: .subheadline) private var stripHeight: CGFloat = 44

    /// The Mac marks a dialog with "…"; iOS does not
    #if os(macOS)
    private static let importTitle: LocalizedStringKey = "Import server…"
    private static let exportTitle: LocalizedStringKey = "Export servers…"
    #else
    private static let importTitle: LocalizedStringKey = "Import server"
    private static let exportTitle: LocalizedStringKey = "Export servers"
    #endif

    @StateObject private var viewModel = ServerListViewModel()
    @StateObject private var metrics = ServerMetricsStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SecuritySettings.gateExportKey) private var gateExport = true

    @State private var addingServer = false
    @State private var reordering = false
    @State private var deploymentToEdit: Deployment?
    @State private var deploymentToDelete: Deployment?
    @State private var confirmedRemoval: Deployment?
    @State private var selectedPage: ServerPage = .all
    @State private var problemFilter: ServerProblem?
    @State private var openedOnlyServer = false
    @State private var navigationPath = NavigationPath()
    @StateObject private var sidePane = SidePaneModel()
    @Environment(\.wideLayout) private var wideLayout
    @ObservedObject private var tour = AppTour.shared
    @State private var tourOpenedServer = false
    @State private var listWidth: CGFloat?
    /// Which card of a pair the finger landed on
    @State private var pressTracker = CardPressTracker()
    @State private var growing: Set<UUID> = []
    /// One card per row, or two half-width ones
    @AppStorage(MetricsDisplaySettings.cardColumnsKey)
    private var cardColumnsRaw = ServerCardColumns.one.rawValue
    @StateObject private var navigator = AppNavigator.shared
    @ObservedObject private var barSettings = TabBarSettings.shared

    @State private var deploymentPendingExport: Deployment?
    @State private var exportFileURLs: [URL] = []
    @State private var showingShareSheet = false
    @State private var exportingSeveral = false
    @State private var chosenForExport: [Deployment] = []
    @State private var choosingForQR = false
    @State private var chosenForQR: [Deployment] = []
    @State private var quickSend: QuickTransferTarget?
    @State private var receivingByQR = false
    /// Import and export offer a file or a QR code
    @State private var askingImportWay = false
    @State private var askingExportWay = false
    @State private var importing = false
    @StateObject private var transfer = ServerTransferModel()
    @State private var renamingGroup: String?
    /// A group being made from the strip's own menu
    @State private var namingNewGroup = false
    @State private var groupToFill: String?
    /// The strip's group order, one name per line
    @AppStorage(ServerGroups.orderKey) private var groupOrderRaw = ""

    var body: some View {
        SidePaneSplit(model: sidePane, wide: wideLayout) {
            NavigationStack(path: $navigationPath) {
                fleetScreen
            }
        } pane: { entry in
            NavigationStack {
                screenDestinations(entry.content)
                    #if os(iOS) || os(tvOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            }
            .id(entry.id)
        }
        .onChange(of: navigationPath.count) { sidePane.close() }
        .onReceive(navigator.$serversTabOpened.dropFirst()) { _ in openOnlyServer() }
        .popToRootOnReselect(.servers) { navigationPath = NavigationPath() }
    }

    private var fleetScreen: some View {
        fleetPresentations
        .onReceive(NotificationCenter.default.publisher(for: .gryonixDeploymentInstalled)) { note in
            guard let id = note.object as? UUID else { return }
            viewModel.load()
            metrics.sync(with: viewModel.deployments)
            metrics.restartPoller(for: id)
        }
        .onReceive(LicenseStore.shared.$status.dropFirst()) { _ in
            viewModel.load()
            metrics.sync(with: viewModel.deployments)
        }
        .onReceive(navigator.$openServerID.compactMap { $0 }) { id in
            openRequestedServer(id)
        }
        .onChange(of: tour.step) { _, step in follow(step?.place) }
        .task {
            viewModel.load()
            openOnlyServerOnce()
            if let id = navigator.openServerID { openRequestedServer(id) }
            #if DEBUG
            if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_ADD"] != nil {
                addingServer = true
            }
            if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_DASHBOARD"] != nil {
                for _ in 0..<40 where viewModel.deployments.isEmpty {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                let log = "fleet=\(viewModel.deployments.count) path=\(navigationPath.count)"
                openRequestedDashboard()
                try? "\(log) after=\(navigationPath.count)".write(
                    toFile: NSTemporaryDirectory() + "hook.txt", atomically: true, encoding: .utf8)
            }
            #endif
        }
        .onAppear {
            metrics.sync(with: viewModel.deployments)
            metrics.retryFailedHosts()
        }
        .onChange(of: viewModel.deployments) { _, deployments in
            Task { @MainActor in metrics.sync(with: deployments) }
            keepSelectionReachable()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: metrics.stopAll()
            default:
                metrics.sync(with: viewModel.deployments)
                metrics.retryFailedHosts()
            }
        }
    }

    private var fleetPresentations: some View {
        serverAlerts(groupPresentations)
    }

    private var groupPresentations: some View {
        screenDestinations(fleetList
        .onReceive(navigator.$serversAction.compactMap { $0 }) { perform($0) }
        .onReceive(navigator.$incomingServerFile.compactMap { $0 }) { url in
            navigator.incomingServerFile = nil
            importFile(at: url)
        }
        .sheet(isPresented: $exportingSeveral, onDismiss: {
            let chosen = chosenForExport
            chosenForExport = []
            Task { await startExport(of: chosen) }
        }) {
            ServerMultiExportView(deployments: viewModel.deployments) { chosen in
                chosenForExport = chosen
                exportingSeveral = false
            }
        }
        .sheet(isPresented: $reordering) {
            ServerReorderView(viewModel: viewModel)
        }
        .modifier(quickTransferSheets)
        .sheet(item: Binding(get: { groupToFill.map(GroupTarget.init) },
                             set: { groupToFill = $0?.name })) { target in
            GroupMembershipView(group: target.name, deployments: viewModel.deployments) {
                setMembership($0, of: target.name)
            }
        }
        .sheet(item: Binding(get: { renamingGroup.map(GroupTarget.init) },
                             set: { renamingGroup = $0?.name })) { target in
            NameEditSheet(title: "Rename group", fieldTitle: "Group", initial: target.name,
                          valid: { ServerGroups.clean($0) != nil }) { name in
                if let name = ServerGroups.clean(name) { rename(group: target.name, to: name) }
            }
        }
        .sheet(isPresented: $namingNewGroup) {
            NameEditSheet(title: "New group", fieldTitle: "Group", initial: "",
                          valid: { ServerGroups.clean($0) != nil }) { name in
                if let name = ServerGroups.clean(name) { groupToFill = name }
            }
        }
        .sheet(isPresented: $addingServer) {
            ServerFormView(mode: .add) { deployment in
                if LicenseStore.isUnlocked { viewModel.upsert(deployment) }
            }
        }
        .sheet(item: $deploymentToEdit) { deployment in
            ServerFormView(mode: .edit(deployment),
                           onSave: { updated in viewModel.upsert(updated) })
        })
    }

    private func openOnlyServerOnce() {
        guard !openedOnlyServer else { return }
        openedOnlyServer = true
        openOnlyServer()
    }

    private func openOnlyServer() {
        viewModel.load()
        guard navigationPath.isEmpty, viewModel.deployments.count == 1,
              let only = viewModel.deployments.first else { return }
        navigationPath.append(only)
    }

    /// Removes the server once its sheet has gone
    private func removeConfirmed() {
        guard let deployment = confirmedRemoval else { return }
        confirmedRemoval = nil
        viewModel.delete(deployment)
    }

    private func screenDestinations(_ base: some View) -> some View {
        base
        .navigationDestination(for: Deployment.self) { deployment in
            DashboardView(deployment: deployment, onUpdate: { updated in
                viewModel.upsert(updated)
            }, onDelete: { deleted in
                viewModel.delete(deleted)
            })
        }
        .navigationDestination(for: MetricsHistoryTarget.self) { ServerPageDestination(value: $0) }
        .navigationDestination(for: EnergyTarget.self) { ServerPageDestination(value: $0) }
        .navigationDestination(for: StorageTarget.self) { ServerPageDestination(value: $0) }
        .navigationDestination(for: CacheDiskTarget.self) { ServerPageDestination(value: $0) }
        .navigationDestination(for: SpeedTestTarget.self) { ServerPageDestination(value: $0) }
        .navigationDestination(for: TopProcessesTarget.self) { ServerPageDestination(value: $0) }
        #if DEBUG
        .navigationDestination(for: MeshDevicesTarget.self) { target in
            MeshDevicesView(viewModel: DashboardViewModel(deployment: target.deployment))
        }
        .navigationDestination(for: DeploymentNodesTarget.self) { target in
            DeploymentNodesView(deployment: target.deployment) { viewModel.upsert($0) }
        }
        #endif
    }

    private func serverAlerts(_ base: some View) -> some View {
        base
            .sheet(item: $deploymentToDelete, onDismiss: removeConfirmed) { deployment in
                ServerRemovalSheet(deployment: deployment) { confirmedRemoval = deployment }
            }
            .alert("Export this server?",
                   isPresented: $deploymentPendingExport.isPresent(),
                   presenting: deploymentPendingExport) { deployment in
                Button("File", role: .destructive) {
                    let toExport = deployment
                    deploymentPendingExport = nil
                    Task { await startExport(of: toExport) }
                }
                .dangerTint()
                Button("QR code", role: .destructive) {
                    let toSend = deployment
                    deploymentPendingExport = nil
                    Task { await startQuickSend([toSend]) }
                }
                .dangerTint()
                Button("Cancel", role: .cancel) { deploymentPendingExport = nil }
            } message: { _ in
                Text("The file carries everything about this server: its configuration, the SSH key, tunnel keys and passwords. The other device can manage, reinstall and repair it exactly as this one does — so share the file only with a device you trust.")
            }
            .confirmationDialog("Import server", isPresented: $askingImportWay, titleVisibility: .visible) {
                Button("File") { importing = true }
                Button("QR code") { receivingByQR = true }
            }
            .confirmationDialog("Export servers", isPresented: $askingExportWay, titleVisibility: .visible) {
                Button("File") { exportingSeveral = true }
                Button("QR code") { startChoosingForQR() }
            }
            .shareSheet(isPresented: $showingShareSheet, items: exportFileURLs)
            .sheet(item: $transfer.prompt) { prompt in
                TransferPassphraseSheet(prompt: prompt, error: transfer.promptError) { passphrase in
                    submit(prompt, passphrase: passphrase)
                } onCancel: {
                    transfer.prompt = nil
                }
            }
            .alert("Replace this server?", isPresented: $transfer.replacing.isPresent(),
                   presenting: transfer.replacing) { _ in
                Button("Replace", role: .destructive) { transfer.confirmReplace(into: viewModel) }
                    .dangerTint()
                Button("Cancel", role: .cancel) { transfer.skipReplace() }
            } message: { incoming in
                Text(verbatim: UIL10n.string(
                    "“%@” is already on this device. Replacing it swaps its SSH key, passwords and pinned host keys for the ones in the file.",
                    incoming.deployment.name))
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.data],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
    }

    /// The list itself, its title and its toolbar
    private var fleetList: some View {
        Group {
            if viewModel.deployments.isEmpty {
                emptyState
            } else {
                cardList
            }
        }
        #if DEBUG
        .overlay {
            if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_FLOATING"] != nil,
               let first = filteredDeployments.first {
                serverCards(for: first)
                    .glassCardFloating()
                    .padding(.horizontal, 20)
            }
        }
        #endif
        .screenTitle("Servers")
        .sectionToolbar(.servers) {
            Button {
                if LicensePrompt.shared.allow() { addingServer = true }
            } label: {
                Label("Add server", systemImage: "plus")
            }
            Button {
                if LicensePrompt.shared.allow() { askingImportWay = true }
            } label: {
                Label(Self.importTitle, systemImage: "square.and.arrow.down")
            }
            if !viewModel.deployments.isEmpty {
                Button {
                    askingExportWay = true
                } label: {
                    Label(Self.exportTitle, systemImage: "square.and.arrow.up")
                }
            }
            if viewModel.deployments.count > 1 {
                Divider()
                Button {
                    reordering = true
                } label: {
                    Label("Reorder Servers", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        #if os(macOS)
        .toolbar {
            if showsTagStrip {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        tagPicker.labelsHidden()
                        groupActionsMenu
                    }
                }
            }
        }
        #endif
    }

    // MARK: - Card list

    private var cardList: some View {
        #if DEBUG
        ScrollViewReader { proxy in
            cardListBody
                .task(id: filteredDeployments.count) {
                    guard let interval = CardResizeProbe.interval else { return }
                    var compact = false
                    if CardResizeProbe.flipsOneCard {
                        for other in viewModel.deployments.dropFirst()
                        where ServerCardLayout.size(of: other, whenUnset: .wide) != .compact {
                            setCardSize(.compact, for: other)
                        }
                    }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(interval))
                        compact.toggle()
                        let flipped = CardResizeProbe.flipsOneCard
                            ? Array(viewModel.deployments.prefix(1))
                            : viewModel.deployments
                        for deployment in flipped {
                            setCardSize(compact ? .compact : .wide, for: deployment)
                        }
                    }
                }
                .task(id: filteredDeployments.count) {
                    guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_SCROLL"] != nil else { return }
                    let ids = filteredDeployments.map(\.id)
                    guard ids.count > 1 else { return }
                    var index = 0
                    let stride = max(1, ids.count / 3)
                    while !Task.isCancelled {
                        index = (index + stride) % ids.count
                        withAnimation(.easeInOut) { proxy.scrollTo(ids[index], anchor: .center) }
                        try? await Task.sleep(for: .milliseconds(330))
                    }
                }
        }
        #else
        cardListBody
        #endif
    }

    @ViewBuilder
    private var cardListBody: some View {
        #if os(macOS)
        serverList(for: filteredDeployments)
            .background(listBackground)
        #else
        serverList(for: filteredDeployments)
            .background(listBackground)
            .overlay(alignment: .top) { tagStrip }
        #endif
    }

    private func explainProblem(_ problem: ServerProblem) {
        let facts = metrics.healthFacts(for: viewModel.deployments)
        let title = UIL10n.string(ServerProblemCards.titleKey(problem))
        AIChatStore.shared.start(AIExplain.problem(problem, facts: facts,
                                                   deployments: viewModel.deployments, title: title))
    }

    private func cardGrid(for row: ServerCardLayout.Row) -> some View {
        Grid(horizontalSpacing: Self.columnGutter, verticalSpacing: 0) {
            GridRow {
                ForEach(row.columns, id: \.first?.id) { column in
                    VStack(spacing: Self.columnGutter) {
                        ForEach(column) { deployment in
                            card(for: deployment, in: row.all)
                                .frame(width: growing.contains(deployment.id)
                                           ? narrowCellWidth : nil,
                                       alignment: .leading)
                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                       alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .top)
                }
                if row.columns.count == 1, row.all.count == 1,
                   cellWidth(for: row.all[0]) == nil,
                   size(of: row.all[0]) == .compact {
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func serverList(for deployments: [Deployment]) -> some View {
        List {
            ServerProblemCards(counts: ServerProblems.counts(metrics.healthFacts(for: self.deployments(on: selectedPage))),
                               selection: $problemFilter,
                               explain: { explainProblem($0) })
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: Self.rowInset, bottom: 6, trailing: Self.rowInset))
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(rows(of: deployments)) { row in
                ServerCardsRow(columns: row.columns.map { column in
                    column.map {
                        ServerCardsRow.Member(id: $0.id,
                                              compact: size(of: $0) == .compact,
                                              width: cellWidth(for: $0))
                    }
                }) {
                cardGrid(for: row)
                }
                .modifier(CardRowChrome())
                .swipeActions(edge: .trailing, allowsFullSwipe: row.all.count == 1) {
                    if row.all.count == 1, let only = row.all.first {
                        Button {
                            deploymentToDelete = only
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .dangerTint()
                        Button {
                            if LicensePrompt.shared.allow(only) { deploymentToEdit = only }
                        } label: {
                            Label("Connection Settings", systemImage: "gearshape")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            GeometryReader { proxy in
                Color.clear.onAppear { listWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in listWidth = width }
            }
        }
        #if !os(macOS)
        .contentMargins(.top, showsTagStrip ? tagStripHeight : 0,
                        for: .scrollContent)
        .bottomBarClearance()
        #endif
        .refreshableWithShortcut {
            viewModel.load()
            await metrics.reconnectAll(viewModel.deployments)
        }
    }

    #if os(macOS)
    /// The selected group's moves, names and files
    private var groupActionsMenu: some View {
        Menu {
            if let group = selectedPage.tag {
                Button("Move left") { moveGroup(group, by: -1) }
                    .disabled(allTags.first == group)
                Button("Move right") { moveGroup(group, by: 1) }
                    .disabled(allTags.last == group)
                Divider()
                Button("Rename group") {
                    renamingGroup = group
                }
                Button("Export group…") { Task { await startGroupExport([group]) } }
                Button("Delete group", role: .destructive) { delete(group: group) }
                    .dangerTint()
                Divider()
            }
            Button("New group…") {
                namingNewGroup = true
            }
            Button("Export all groups…") { Task { await startGroupExport(allTags) } }
            Button("Import groups…") { importGroups() }
        } label: {
            Label("Groups", systemImage: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Groups")
    }
    #endif

    @ViewBuilder
    private var tagPicker: some View {
        #if os(iOS)
        if barSettings.groupStripStyle == .custom {
            GlassSegmentStrip(
                items: tagSegments.map {
                    StripItem(id: $0.identifier, title: $0.title,
                              identifier: "fleet.group.\($0.identifier)")
                },
                selection: Binding(get: { selectedPage.identifier },
                                   set: { id in
                                       guard let page = tagSegments.first(where: {
                                           $0.identifier == id
                                       })?.value else { return }
                                       selectedPage = page
                                   }),
                identifier: "fleet.groups",
                probe: "groups",
                menu: { id in
                    tagSegments.first { $0.identifier == id }.map { groupMenu(for: $0.value) }
                },
                dragToSwitch: true)
        } else {
            systemTagPicker
        }
        #else
        systemTagPicker
        #endif
    }

    private var systemTagPicker: some View {
        Picker("Tag", selection: $selectedPage) {
            ForEach(tagSegments) { segment in
                Text(verbatim: segment.title).tag(segment.value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        #if os(iOS)
        .controlSize(.large)
        .frame(height: stripHeight)
        .segmentMenus(count: tagSegments.count, probe: "groups") { index in
            guard tagSegments.indices.contains(index) else { return nil }
            return groupMenu(for: tagSegments[index].value)
        }
        #endif
    }

    @ViewBuilder
    private var tagStrip: some View {
        if showsTagStrip {
            tagPicker
                .padding(.horizontal, 16)
                // Room above for the lens that lifts while held.
                .padding(.top, 14)
        }
    }

    /// One choice on the fleet's tag strip
    fileprivate struct TagSegment: Identifiable {
        let value: ServerPage
        let title: String
        var id: ServerPage { value }

        var identifier: String { value.identifier }

        init(_ value: ServerPage, _ title: String) {
            self.value = value
            self.title = title
        }
    }

    private var tagSegments: [TagSegment] {
        [TagSegment(.all, UIL10n.string("All"))]
            + allTags.map { TagSegment(.tag($0), $0) }
    }

    private var tagStripHeight: CGFloat {
        #if os(iOS) || os(tvOS)
        barSettings.groupStripStyle == .custom ? Self.customTagStripHeight : 14 + stripHeight + 6
        #else
        Self.customTagStripHeight
        #endif
    }

    private static let customTagStripHeight: CGFloat = 60
    /// The horizontal inset every card row is drawn with
    static let rowInset: CGFloat = 16

    /// The gap between two cards sharing a row
    static let columnGutter: CGFloat = 10

    private var cardColumns: ServerCardColumns {
        MetricsDisplaySettings.cardColumns(from: cardColumnsRaw)
    }

    private func cellWidth(for deployment: Deployment) -> CGFloat? {
        ServerCardLayout.cellWidth(of: deployment, listWidth: listWidth,
                                   inset: Self.rowInset, gutter: Self.columnGutter,
                                   whenUnset: cardColumns.cardSize)
    }

    private func size(of deployment: Deployment) -> ServerCardSize {
        ServerCardLayout.size(of: deployment, whenUnset: cardColumns.cardSize)
    }

    private var cardWidth: CGFloat? {
        guard let listWidth else { return nil }
        let columns = CGFloat(cardColumns.count)
        let inner = (listWidth - Self.rowInset * 2
                     - Self.columnGutter * (columns - 1)) / columns
        return inner > 0 ? inner : nil
    }

    /// One machine: one card
    private func serverCards(for deployment: Deployment) -> some View {
        ServerCardRow(deployment: deployment, metrics: metrics.card(for: deployment.id),
                      compact: size(of: deployment) == .compact,
                      width: cellWidth(for: deployment),
                      onWidthArrived: { finishGrowing(deployment.id) })
            .modifier(TourTargetIf(deployment.id == viewModel.deployments.first?.id, .serverCard))
    }

    private func card(for deployment: Deployment, in row: [Deployment]) -> some View {
        serverCards(for: deployment)
            .contentShape(Rectangle())
            .onTapGesture { open(deployment) }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(deployment) }
        #if !os(tvOS)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.05, maximumDistance: 50)
                .onEnded { _ in pressTracker.press(deployment.id) })
        .simultaneousGesture(
            LongPressGesture(minimumDuration: ServerCardHold.menuDelay, maximumDistance: 50)
                .onEnded { _ in pressTracker.markHeld(deployment.id) })
        #endif
        .glassCardContextMenu {
            contextMenu { pressTracker.target(in: row, fallback: deployment) }
        }
    }

    /// A tap on the card; buttons inside it answer first
    private func open(_ deployment: Deployment) {
        guard !pressTracker.wasHeld(deployment.id), LicensePrompt.shared.allow(deployment) else { return }
        navigationPath.append(deployment)
    }

    private func rows(of deployments: [Deployment]) -> [ServerCardLayout.Row] {
        guard !growing.isEmpty else {
            return ServerCardLayout.rows(of: deployments, whenUnset: cardColumns.cardSize)
        }
        let packed = deployments.map { deployment -> Deployment in
            guard growing.contains(deployment.id) else { return deployment }
            var narrow = deployment
            narrow.cardSize = .compact
            return narrow
        }
        let byID = Dictionary(uniqueKeysWithValues: deployments.map { ($0.id, $0) })
        return ServerCardLayout.rows(of: packed, whenUnset: cardColumns.cardSize).map { row in
            ServerCardLayout.Row(columns: row.columns.map { column in
                column.map { byID[$0.id] ?? $0 }
            })
        }
    }

    @ViewBuilder
    private func contextMenu(_ target: @escaping () -> Deployment) -> some View {
        Menu {
            appearanceChoices(target)
        } label: {
            Label("Appearance", systemImage: "paintbrush")
        }
        Button {
            let deployment = target()
            if LicensePrompt.shared.allow(deployment) { deploymentToEdit = deployment }
        } label: {
            Label("Connection Settings", systemImage: "gearshape")
        }
        Button {
            deploymentPendingExport = target()
        } label: {
            Label("Export server", systemImage: "square.and.arrow.up")
        }
        Button(role: .destructive) {
            deploymentToDelete = target()
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .dangerTint()
    }

    private func appearanceChoices(_ target: @escaping () -> Deployment) -> some View {
        ServerAppearanceChoices(deployment: target,
                                setCardSize: { setCardSize($0, for: target()) },
                                setIndicatorStyle: { setIndicatorStyle($0, for: target()) },
                                setTint: { setTint($0, for: target()) })
    }

    private func menuChoice(_ title: LocalizedStringKey, picked: Bool,
                            _ choose: @escaping () -> Void) -> some View {
        MenuChoice(title, picked: picked, choose: choose)
    }

    private func startExport(of deployment: Deployment) async {
        if gateExport {
            let reason = UIL10n.string("Unlock to export this server")
            guard await BiometricGate.authenticate(reason: reason) else { return }
        }
        transfer.askToExport([deployment])
    }

    private func submit(_ prompt: ServerTransferModel.Prompt, passphrase: String) {
        switch prompt {
        case .export(let deployments):
            transfer.prompt = nil
            Task { await writeExports(deployments, passphrase: passphrase) }
        case .exportGroups(let groups):
            transfer.prompt = nil
            Task { await writeGroupExport(groups, passphrase: passphrase) }
        case .unlock(let data):
            transfer.unlock(data, passphrase: passphrase, into: viewModel)
        }
    }

    // MARK: - QR transfer

    private var quickTransferSheets: QuickTransferSheets {
        QuickTransferSheets(viewModel: viewModel, transfer: transfer, choosing: $choosingForQR,
                            chosen: $chosenForQR, sending: $quickSend, receiving: $receivingByQR) { chosen in
            await startQuickSend(chosen)
        }
    }

    private func startChoosingForQR() {
        if viewModel.deployments.count == 1 {
            Task { await startQuickSend(viewModel.deployments) }
        } else {
            choosingForQR = true
        }
    }

    private func startQuickSend(_ deployments: [Deployment]) async {
        guard !deployments.isEmpty else { return }
        if gateExport {
            let reason = UIL10n.string("Unlock to export these servers")
            guard await BiometricGate.authenticate(reason: reason) else { return }
        }
        quickSend = QuickTransferTarget(deployments: deployments)
    }

    /// Several servers in one share
    private func startExport(of deployments: [Deployment]) async {
        guard !deployments.isEmpty else { return }
        if gateExport {
            let reason = UIL10n.string("Unlock to export these servers")
            guard await BiometricGate.authenticate(reason: reason) else { return }
        }
        transfer.askToExport(deployments)
    }

    /// Writes the sealed files and opens the share sheet
    private func writeExports(_ deployments: [Deployment], passphrase: String) async {
        cleanupExportFile()
        var written: [URL] = []
        var failed: [String] = []
        for deployment in deployments {
            guard let data = await viewModel.exportData(for: deployment, passphrase: passphrase) else {
                failed.append(deployment.name)
                continue
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(DeploymentTransferService.fileName(for: deployment))
            do {
                try data.write(to: url, options: .atomic)
                written.append(url)
            } catch {
                failed.append(deployment.name)
            }
        }
        if !failed.isEmpty {
            viewModel.errorMessage = UIL10n.string("Could not export: %@",
                                                   failed.joined(separator: ", "))
        }
        guard !written.isEmpty else { return }
        exportFileURLs = written
        showingShareSheet = true
    }

    /// Writes one sealed file holding the groups and their servers
    private func writeGroupExport(_ groups: [String], passphrase: String) async {
        cleanupExportFile()
        guard let data = await viewModel.groupExportData(groups: groups, passphrase: passphrase) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(ServerGroupBundle.fileName(for: groups))
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            viewModel.errorMessage = UIL10n.string("Could not export: %@", groups.joined(separator: ", "))
            return
        }
        exportFileURLs = [url]
        showingShareSheet = true
    }

    private func startGroupExport(_ groups: [String]) async {
        guard !groups.isEmpty else { return }
        if gateExport {
            let reason = UIL10n.string("Unlock to export these servers")
            guard await BiometricGate.authenticate(reason: reason) else { return }
        }
        transfer.askToExport(groups: groups)
    }

    #if DEBUG
    /// Adds a debug server as an installed local server
    private func seedTestStand() -> Deployment {
        let env = ProcessInfo.processInfo.environment
        let id = UUID(uuidString: "6D3E0000-DE40-4000-8000-0000000000AA") ?? UUID()
        let services = env["GRYONIXNEXUS_DEBUG_STAND_SERVICES"].map {
            Set($0.split(separator: ",").map { ServiceID(rawValue: String($0)) })
        } ?? [.homeAssistant, .mosquitto]
        let stand = Deployment(id: id, name: env["GRYONIXNEXUS_DEBUG_STAND_NAME"] ?? "orion", topology: .singleHost,
                               domain: env["GRYONIXNEXUS_DEBUG_STAND_DOMAIN"] ?? "home.local",
                               entry: HostEndpoint(host: env["GRYONIXNEXUS_DEBUG_STAND_HOST"] ?? "192.168.178.100",
                                                   user: env["GRYONIXNEXUS_DEBUG_STAND_USER"] ?? "admin"),
                               services: services, usesAgent: true, scope: .localOnly)
        viewModel.upsert(stand)
        ConfiguratorStore.shared.saveDeploymentConfig(ConfiguratorDraft(recovering: stand))
        let key = try? KeychainSSHIdentityStore(deploymentID: id).loadOrGenerate().publicKeyOpenSSH
        try? key?.write(toFile: NSTemporaryDirectory() + "stand-key.pub", atomically: true, encoding: .utf8)
        return stand
    }

    private func openRequestedDashboard() {
        let env = ProcessInfo.processInfo.environment
        if env["GRYONIXNEXUS_DEBUG_TEST_STAND"] != nil, navigationPath.isEmpty {
            navigationPath.append(seedTestStand())
            return
        }
        guard let requested = env["GRYONIXNEXUS_DEMO_OPEN_DASHBOARD"],
              navigationPath.count <= 1 else { return }
        let index = max((Int(requested) ?? 1) - 1, 0)
        let byID = UUID(uuidString: requested).flatMap { id in viewModel.deployments.first { $0.id == id } }
        guard let first = byID ?? (viewModel.deployments.indices.contains(index)
                ? viewModel.deployments[index] : viewModel.deployments.first) else { return }
        if env["GRYONIXNEXUS_DEMO_SAVED_CONFIG"] != nil {
            let draft = ConfiguratorDraft(recovering: first)
            ConfiguratorStore.shared.saveDeploymentConfig(draft)
        }
        var path = NavigationPath()
        path.append(first)
        if env["GRYONIXNEXUS_DEMO_OPEN_HISTORY"] != nil {
            let metric = env["GRYONIXNEXUS_DEMO_HISTORY_METRIC"].flatMap(HistoryMetric.init(rawValue:))
            path.append(MetricsHistoryTarget(deployment: first, host: .vps, metric: metric))
        }
        if env["GRYONIXNEXUS_DEMO_OPEN_ENERGY"] != nil {
            path.append(EnergyTarget(deployment: first, host: .vps, cores: 4))
        }
        navigationPath = path
        if env["GRYONIXNEXUS_DEMO_OPEN_MESH"] != nil {
            navigationPath.append(MeshDevicesTarget(deployment: first))
        }
        if env["GRYONIXNEXUS_DEMO_OPEN_NODES"] != nil {
            let target = viewModel.deployments.first(where: \.isMultiHost) ?? first
            navigationPath.append(DeploymentNodesTarget(deployment: target))
        }
    }
    #endif

    /// Opens or closes the first server as the tour moves
    private func follow(_ place: AppTourPlace?) {
        switch place {
        case .server:
            guard navigationPath.isEmpty, let first = viewModel.deployments.first else { return }
            navigationPath.append(first)
            tourOpenedServer = true
        case .fleet, nil:
            guard tourOpenedServer else { return }
            navigationPath = NavigationPath()
            tourOpenedServer = false
        }
    }

    private func openRequestedServer(_ id: UUID) {
        performOpen(id)
    }

    private func performOpen(_ id: UUID) {
        viewModel.load()
        guard let deployment = viewModel.deployments.first(where: { $0.id == id }) else {
            navigator.openServerID = nil
            return
        }
        navigator.openServerID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.openAfterSheets) {
            navigationPath = NavigationPath()
            navigationPath.append(deployment)
        }
    }

    /// Lets a closing sheet and tab switch settle first
    private static let openAfterSheets: TimeInterval = 0.45

    private func cleanupExportFile() {
        for url in exportFileURLs { try? FileManager.default.removeItem(at: url) }
        exportFileURLs = []
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importFile(at: url)
        case .failure(let error):
            viewModel.errorMessage = UIL10n.string("Failed to import the server: %@", error.localizedDescription)
        }
    }

    private func importFile(at url: URL) {
        guard LicensePrompt.shared.allow() else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let importLimit = 1_048_576
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > importLimit {
                throw ServerControlError.fileTooLarge(path: url.lastPathComponent,
                                                      size: UInt64(size),
                                                      limit: UInt64(importLimit))
            }
            transfer.received(try Data(contentsOf: url), into: viewModel)
        } catch {
            viewModel.errorMessage = UIL10n.string("Failed to import the server: %@", error.localizedDescription)
        }
    }

    /// The tab bar menu's three verbs, in one place
    private func perform(_ action: AppNavigator.ServersAction) {
        navigator.serversAction = nil
        switch action {
        case .add: if LicensePrompt.shared.allow() { addingServer = true }
        case .importServer: if LicensePrompt.shared.allow() { askingImportWay = true }
        case .export: askingExportWay = true
        }
    }

    private func setIndicatorStyle(_ style: MetricsIndicatorStyle?, for deployment: Deployment) {
        var updated = deployment
        updated.metricsIndicatorStyle = style
        withAnimation(.snappy(duration: 0.3)) { viewModel.updateAppearance(updated) }
    }

    private func setTint(_ tint: String?, for deployment: Deployment) {
        var updated = deployment
        updated.tintName = tint
        withAnimation(.snappy(duration: 0.3)) { viewModel.updateAppearance(updated) }
    }

    private func setCardSize(_ size: ServerCardSize?, for deployment: Deployment) {
        var updated = deployment
        updated.cardSize = size
        let grows = ServerCardLayout.size(of: deployment, whenUnset: cardColumns.cardSize) == .compact
            && ServerCardLayout.size(of: updated, whenUnset: cardColumns.cardSize) != .compact
        if grows { growing.insert(deployment.id) }
        withAnimation(.snappy(duration: 0.3)) { viewModel.updateAppearance(updated) }
        guard grows else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + ServerCardRow.slide + 1.5) {
            finishGrowing(deployment.id)
        }
    }

    private var narrowCellWidth: CGFloat? {
        guard let listWidth else { return nil }
        let inner = (listWidth - Self.rowInset * 2 - Self.columnGutter) / 2
        return inner > 0 ? inner : nil
    }

    private func finishGrowing(_ id: UUID) {
        guard growing.contains(id) else { return }
        withAnimation(.snappy(duration: 0.3)) { _ = growing.remove(id) }
    }

    private var allTags: [String] {
        ServerGroups.known(in: viewModel.deployments, order: ServerGroups.parse(groupOrderRaw))
    }

    /// One place left or right on the strip
    private func moveGroup(_ group: String, by offset: Int) {
        guard let order = ServerGroups.moving(group, by: offset, among: allTags,
                                              stored: ServerGroups.parse(groupOrderRaw)) else { return }
        withAnimation(.snappy(duration: 0.25)) { groupOrderRaw = ServerGroups.format(order) }
    }

    private func importGroups() {
        if LicensePrompt.shared.allow() { importing = true }
    }

    private func keepSelectionReachable() {
        guard let tag = selectedPage.tag, !showsTagStrip || !allTags.contains(tag) else { return }
        selectedPage = .all
    }

    /// A strip only for two or more groups
    private var showsTagStrip: Bool { allTags.count >= 2 }

    #if os(iOS) || os(tvOS)
    /// The held segment's own menu
    private func groupMenu(for page: ServerPage) -> UIMenu {
        guard let group = page.tag else {
            return UIMenu(title: UIL10n.string("All"), children: [newGroupAction(), groupFilesMenu()])
        }
        let members = ServerGroups.members(of: group, in: viewModel.deployments)
        let membership = UIMenu(title: "", options: .displayInline, children:
            viewModel.deployments.map { deployment in
                let inside = members.contains { $0.id == deployment.id }
                return UIAction(title: deployment.name, state: inside ? .on : .off) { _ in
                    setMembership(inside ? [] : [deployment.id], of: group, toggling: deployment.id)
                }
            })
        let edits = UIMenu(title: "", options: .displayInline, children: [
            UIAction(title: UIL10n.string("Rename group"),
                     image: UIImage(systemName: "pencil")) { _ in
                renamingGroup = group
            },
            newGroupAction(),
            UIAction(title: UIL10n.string("Delete group"),
                     image: UIImage(systemName: "trash"),
                     attributes: .destructive) { _ in delete(group: group) },
        ])
        let tags = allTags
        let moves = UIMenu(title: "", options: .displayInline, children: [
            UIAction(title: UIL10n.string("Move left"), image: UIImage(systemName: "arrow.left"),
                     attributes: tags.first == group ? .disabled : []) { _ in moveGroup(group, by: -1) },
            UIAction(title: UIL10n.string("Move right"), image: UIImage(systemName: "arrow.right"),
                     attributes: tags.last == group ? .disabled : []) { _ in moveGroup(group, by: 1) },
        ])
        let export = UIAction(title: UIL10n.string("Export group…"),
                              image: UIImage(systemName: "square.and.arrow.up")) { _ in
            Task { await startGroupExport([group]) }
        }
        return UIMenu(title: group, children: [membership, moves,
                                               UIMenu(title: "", options: .displayInline, children: [export]),
                                               edits])
    }

    /// Every group to one file, or groups from one
    private func groupFilesMenu() -> UIMenu {
        UIMenu(title: "", options: .displayInline, children: [
            UIAction(title: UIL10n.string("Export all groups…"),
                     image: UIImage(systemName: "square.and.arrow.up.on.square"),
                     attributes: allTags.isEmpty ? .disabled : []) { _ in
                Task { await startGroupExport(allTags) }
            },
            UIAction(title: UIL10n.string("Import groups…"),
                     image: UIImage(systemName: "square.and.arrow.down")) { _ in importGroups() },
        ])
    }

    private func newGroupAction() -> UIAction {
        UIAction(title: UIL10n.string("New group…"), image: UIImage(systemName: "plus")) { _ in
            namingNewGroup = true
        }
    }
    #endif

    private func setMembership(_ members: Set<UUID>, of group: String) {
        for deployment in viewModel.deployments {
            let wanted = members.contains(deployment.id)
            let has = deployment.tags.contains { $0.caseInsensitiveCompare(group) == .orderedSame }
            guard wanted != has else { continue }
            var updated = deployment
            updated.tags = ServerGroups.setting(wanted, of: group, in: deployment.tags)
            viewModel.updateAppearance(updated)
        }
        keepSelectionReachable()
    }

    private func setMembership(_ ignored: Set<UUID>, of group: String, toggling id: UUID) {
        guard let deployment = viewModel.deployments.first(where: { $0.id == id }) else { return }
        let has = deployment.tags.contains { $0.caseInsensitiveCompare(group) == .orderedSame }
        var updated = deployment
        updated.tags = ServerGroups.setting(!has, of: group, in: deployment.tags)
        viewModel.updateAppearance(updated)
        keepSelectionReachable()
    }

    private func rename(group: String, to name: String) {
        for deployment in ServerGroups.members(of: group, in: viewModel.deployments) {
            var updated = deployment
            updated.tags = ServerGroups.setting(true, of: name,
                                                in: ServerGroups.setting(false, of: group,
                                                                         in: deployment.tags))
            viewModel.updateAppearance(updated)
        }
        if selectedPage.tag == group { selectedPage = .tag(name) }
        groupOrderRaw = ServerGroups.format(
            ServerGroups.renaming(group, to: name, in: ServerGroups.parse(groupOrderRaw)))
    }

    private func delete(group: String) {
        setMembership([], of: group)
        groupOrderRaw = ServerGroups.format(ServerGroups.removing(group, from: ServerGroups.parse(groupOrderRaw)))
    }

    private func deployments(on page: ServerPage) -> [Deployment] {
        guard let tag = page.tag else { return viewModel.deployments }
        return viewModel.deployments.filter { $0.tags.contains(tag) }
    }

    private var filteredDeployments: [Deployment] {
        var list = deployments(on: selectedPage)
        if let problem = problemFilter {
            let ids = ServerProblems.ids(with: problem, in: metrics.healthFacts(for: list))
            list = list.filter { ids.contains($0.id) }
        }
        return ServerListOrdering.ordered(list) { metrics.offlineIDs.contains($0.id) }
    }

    private var listBackground: Color {
        #if os(iOS) || os(tvOS)
        Color(.systemGroupedBackground)
        #else
        Color.clear
        #endif
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No servers yet")
                .font(.title3.weight(.semibold))
            Text("Add a server with the \"+\" button, or generate a configuration in the Configurator tab with dashboard access enabled — the server will appear here automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                if LicensePrompt.shared.allow() { addingServer = true }
            } label: {
                Text("Add Server")
                    .padding(.horizontal, 8)
            }
            .prominentActionButtonStyle()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Which slice of the fleet is on screen
private enum ServerPage: Hashable {
    case all
    case tag(String)

    /// A stable name for this page — see `TagSegment.identifier`
    var identifier: String {
        switch self {
        case .all: return "all"
        case .tag(let tag): return "tag:" + tag
        }
    }

    /// nil for "All" — the whole fleet
    var tag: String? {
        if case .tag(let tag) = self { return tag }
        return nil
    }
}

#Preview {
    ServerListView()
}

private struct CardRowChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: ServerListView.rowInset,
                                      bottom: 6, trailing: ServerListView.rowInset))
            .listRowBackground(Color.clear)
    }
}

extension Binding {
    func isPresent<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(get: { self.wrappedValue != nil },
                      set: { if !$0 { self.wrappedValue = nil } })
    }
}

/// A tour target on one view only
struct TourTargetIf: ViewModifier {
    let isTarget: Bool
    let target: AppTourTarget

    init(_ isTarget: Bool, _ target: AppTourTarget) {
        self.isTarget = isTarget
        self.target = target
    }

    func body(content: Content) -> some View {
        if isTarget { content.appTourTarget(target) } else { content }
    }
}
