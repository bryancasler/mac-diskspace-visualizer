import QuickLook
import SwiftUI

struct MainView: View {
    @Environment(ScanViewModel.self) private var vm
    @State private var showCollector = false
    @State private var showReclaimables = false
    @AppStorage("vizMode") private var vizMode = "sunburst"

    var body: some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            BreadcrumbView()
            Divider()
            HSplitView {
                sunburst
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                rightPane
                    .frame(minWidth: 340, idealWidth: 440)
            }
            Divider()
            DetailBar()
        }
        .searchable(text: $vm.searchQuery, placement: .toolbar, prompt: "Search scanned files")
        .onChange(of: vm.searchQuery) {
            if !vm.searchQuery.isEmpty { vm.paneMode = .files }
        }
        .quickLookPreview($vm.previewURL)
        .confirmationDialog(
            trashTitle,
            isPresented: Binding(
                get: { vm.pendingTrash != nil },
                set: { if !$0 { vm.pendingTrash = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash (frees \(Format.bytes(pendingTrashTotal)))", role: .destructive) {
                if let nodes = vm.pendingTrash { vm.trash(nodes) }
                vm.pendingTrash = nil
                vm.pendingTrashWarning = nil
            }
            Button("Cancel", role: .cancel) {
                vm.pendingTrash = nil
                vm.pendingTrashWarning = nil
            }
        } message: {
            Text(vm.pendingTrashWarning ?? "You can restore \(pendingTrashIsPlural ? "these" : "it") from the Trash until you empty it.")
        }
        .sheet(isPresented: $showReclaimables) {
            ReclaimablesView()
        }
        .inspector(isPresented: $showCollector) {
            CollectorView()
                .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    vm.goUp()
                } label: {
                    Label("Up", systemImage: "arrow.up")
                }
                .disabled(vm.path.count <= 1)
                .help("Go to the enclosing folder")
            }
            ToolbarItemGroup {
                Picker("View", selection: $vizMode) {
                    Image(systemName: "chart.pie").tag("sunburst")
                        .help("Sunburst — best for structure")
                    Image(systemName: "square.grid.2x2").tag("treemap")
                        .help("Treemap — best for spotting big files")
                }
                .pickerStyle(.segmented)

                Picker("Pane", selection: $vm.paneMode) {
                    ForEach(ScanViewModel.PaneMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Contents of the current folder, or the largest files in scope")

                Button {
                    vm.rescan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .help("Scan \(vm.root?.name ?? "") again")
                Button {
                    vm.backToWelcome()
                } label: {
                    Label("New Scan", systemImage: "internaldrive")
                }
                .help("Choose another disk or folder")

                Button {
                    showReclaimables = true
                } label: {
                    Label("Reclaim", systemImage: "sparkles")
                }
                .help("Known caches, dev cruft, and snapshots you can free")

                Button {
                    showCollector.toggle()
                } label: {
                    Label("Collector", systemImage: "basket")
                }
                .badge(vm.collector.count)
                .help(vm.collector.isEmpty
                      ? "Collect items while exploring, delete them all at once"
                      : "\(vm.collector.count) items — \(Format.bytes(vm.collectorTotal))")
            }
        }
        .onChange(of: vm.collector.count) { oldCount, newCount in
            if newCount > oldCount { showCollector = true }
        }
    }

    private var pendingTrashIsPlural: Bool {
        (vm.pendingTrash?.count ?? 0) != 1
    }

    private var trashTitle: String {
        guard let nodes = vm.pendingTrash else { return "" }
        if let only = nodes.first, nodes.count == 1 {
            return "Move \"\(only.name)\" to the Trash?"
        }
        return "Move \(nodes.count) items to the Trash?"
    }

    private var pendingTrashTotal: Int64 {
        vm.pendingTrash?.reduce(0) { $0 + $1.size } ?? 0
    }

    @ViewBuilder
    private var rightPane: some View {
        switch vm.paneMode {
        case .contents: FileListView()
        case .files: FilesPane()
        case .duplicates: DuplicatesView()
        case .changes: DiffView()
        }
    }

    private var sunburst: some View {
        Group {
            if let current = vm.current {
                if vizMode == "treemap" {
                    TreemapView(
                        center: current,
                        tick: vm.tick,
                        selection: vm.selection,
                        onSelect: { vm.select($0) },
                        onDrill: { vm.drill(into: $0) },
                        onUp: { vm.goUp() },
                        onCollect: { vm.addToCollector($0) },
                        onTrash: { vm.requestTrash([$0]) },
                        onReveal: { vm.reveal($0) }
                    )
                    .padding(8)
                } else {
                    SunburstView(
                        center: current,
                        tick: vm.tick,
                        selection: vm.selection,
                        onSelect: { vm.select($0) },
                        onDrill: { vm.drill(into: $0) },
                        onUp: { vm.goUp() },
                        onCollect: { vm.addToCollector($0) },
                        onTrash: { vm.requestTrash([$0]) },
                        onReveal: { vm.reveal($0) }
                    )
                    .padding(8)
                }
            } else {
                Text("Nothing scanned")
            }
        }
    }
}

struct ScanningView: View {
    @Environment(ScanViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning…")
                .font(.title2.bold())
            Text("\(vm.scannedItems.formatted()) items — \(Format.bytes(vm.scannedBytes))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(vm.scanningPath)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 480)
            Button("Cancel") {
                vm.cancelScan()
            }
            .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ContentView: View {
    @Environment(ScanViewModel.self) private var vm

    var body: some View {
        Group {
            switch vm.phase {
            case .welcome: WelcomeView()
            case .scanning: ScanningView()
            case .done: MainView()
            }
        }
        .frame(minWidth: 960, minHeight: 620)
    }
}
