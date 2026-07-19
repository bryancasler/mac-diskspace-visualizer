import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class ScanViewModel {
    enum Phase {
        case welcome
        case scanning
        case done
    }

    var phase: Phase = .welcome
    var root: FileNode?
    /// Navigation stack from scan root down to the currently focused directory.
    var path: [FileNode] = []
    var tableSelection: FileNode.ID?
    var selection: FileNode?
    /// Bumped whenever the tree mutates so views re-derive from the class tree.
    var tick = 0

    var reclaimedBytes: Int64 = 0
    var inaccessibleCount = 0
    var lastError: String?
    /// When the scan root is a whole volume: bytes the OS reports as used.
    /// Files can't fully account for this (snapshots, purgeable space).
    var volumeUsedBytes: Int64?

    // Live scan progress
    var scannedItems = 0
    var scannedBytes: Int64 = 0
    var scanningPath = ""
    var scanDuration: TimeInterval = 0

    private let progress = ProgressBox()
    private var cancelFlag: CancelFlag?
    private var scanTask: Task<Void, Never>?
    private var progressTimer: Timer?
    private var scanStart: Date?

    var current: FileNode? { path.last }

    var currentChildren: [FileNode] {
        _ = tick
        return current?.children ?? []
    }

    // MARK: - Scanning

    func startScan(url: URL) {
        guard phase != .scanning else { return }
        phase = .scanning
        root = nil
        path = []
        selection = nil
        tableSelection = nil
        lastError = nil
        let volumeKeys: Set<URLResourceKey> = [.isVolumeKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        if let values = try? url.resourceValues(forKeys: volumeKeys),
           values.isVolume == true,
           let total = values.volumeTotalCapacity,
           let available = values.volumeAvailableCapacity {
            volumeUsedBytes = Int64(total - available)
        } else {
            volumeUsedBytes = nil
        }
        progress.reset()
        scannedItems = 0
        scannedBytes = 0
        scanningPath = url.path
        scanStart = Date()

        let flag = CancelFlag()
        cancelFlag = flag
        let box = progress

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            let snap = box.snapshot
            Task { @MainActor in
                guard let self, self.phase == .scanning else { return }
                self.scannedItems = snap.items
                self.scannedBytes = snap.bytes
                self.scanningPath = snap.path
            }
        }

        scanTask = Task.detached(priority: .userInitiated) { [vm = self] in
            let scanner = DiskScanner(progress: box, cancel: flag)
            do {
                let node = try scanner.scan(url: url)
                await MainActor.run { vm.finishScan(with: node) }
            } catch {
                await MainActor.run { vm.abortScan(error: error) }
            }
        }
    }

    private func finishScan(with node: FileNode) {
        stopProgressTimer()
        scanDuration = scanStart.map { Date().timeIntervalSince($0) } ?? 0
        let snap = progress.snapshot
        scannedItems = snap.items
        inaccessibleCount = snap.inaccessible
        root = node
        path = [node]
        phase = .done
        tick += 1
        duplicateGroups = nil
        diffBaseline = nil
        lastSavedSnapshot = try? ScanStore.save(root: node)
        refreshBaselines()
    }

    private func abortScan(error: Error) {
        stopProgressTimer()
        if !(error is CancellationError) {
            lastError = error.localizedDescription
        }
        phase = .welcome
    }

    func cancelScan() {
        cancelFlag?.cancel()
        scanTask?.cancel()
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Navigation

    func drill(into node: FileNode) {
        guard node.isDirectory, !node.isSynthetic else { return }
        path.append(node)
        selection = nil
        tableSelection = nil
        tick += 1
    }

    func goUp() {
        guard path.count > 1 else { return }
        path.removeLast()
        selection = nil
        tableSelection = nil
        tick += 1
    }

    func navigate(to node: FileNode) {
        guard let index = path.firstIndex(where: { $0 === node }) else { return }
        path = Array(path[...index])
        selection = nil
        tableSelection = nil
        tick += 1
    }

    func backToWelcome() {
        cancelScan()
        phase = .welcome
        root = nil
        path = []
        selection = nil
        tableSelection = nil
    }

    func rescan() {
        guard let rootURL = root?.url else { return }
        startScan(url: rootURL)
    }

    func select(_ node: FileNode?) {
        selection = node
        tableSelection = node?.id
    }

    /// Resolves `selection` from `tableSelection` against whichever row set
    /// the current pane is showing — Contents and Files each maintain their
    /// own row list, but share the same underlying selection state.
    func syncSelectionFromTable() {
        let rows = paneMode == .files ? filesPaneRows : currentChildren
        selection = rows.first { $0.id == tableSelection }
    }

    // MARK: - Right pane modes

    enum PaneMode: String, CaseIterable, Identifiable {
        case contents = "Contents"
        case files = "Files"
        case duplicates = "Duplicates"
        case changes = "Changes"
        var id: String { rawValue }
    }

    enum FilesScope: String, CaseIterable, Identifiable {
        case entireScan = "Entire Scan"
        case currentFolder = "This Folder"
        var id: String { rawValue }
    }

    enum AgeFilter: String, CaseIterable, Identifiable {
        case any = "Any Age"
        case sixMonths = "6 mo+"
        case oneYear = "1 yr+"
        case twoYears = "2 yr+"
        var id: String { rawValue }

        var cutoff: Int64? {
            let now = Int64(Date().timeIntervalSince1970)
            switch self {
            case .any: return nil
            case .sixMonths: return now - 183 * 86400
            case .oneYear: return now - 365 * 86400
            case .twoYears: return now - 730 * 86400
            }
        }
    }

    var paneMode: PaneMode = .contents {
        didSet {
            // A stale selection from one pane's row list must never carry
            // over and accidentally resolve against an unrelated row here.
            guard oldValue != paneMode else { return }
            selection = nil
            tableSelection = nil
        }
    }
    var filesScope: FilesScope = .entireScan
    var ageFilter: AgeFilter = .any
    var searchQuery = ""
    var previewURL: URL?

    /// Rows for the flat Files pane: search results when a query is active,
    /// otherwise the largest (optionally stale) files in scope.
    var filesPaneRows: [FileNode] {
        _ = tick
        let base = filesScope == .entireScan ? root : current
        guard let base else { return [] }
        if !searchQuery.isEmpty {
            return base.search(query: searchQuery, minSize: 0)
        }
        return base.collectFiles(limit: 200, minSize: 1, olderThan: ageFilter.cutoff)
    }

    /// Navigate so `node` is visible: directories become the focused folder,
    /// files focus their parent folder and select the file.
    func focus(on node: FileNode) {
        guard let root else { return }
        var chain: [FileNode] = []
        var cursor: FileNode? = node
        while let current = cursor {
            chain.append(current)
            if current === root { break }
            cursor = current.parent
        }
        guard chain.last === root else { return }
        let fullPath = Array(chain.reversed())
        if node.isDirectory && !node.isSynthetic {
            path = fullPath
            selection = nil
            tableSelection = nil
        } else {
            path = Array(fullPath.dropLast())
            select(node)
        }
        tick += 1
    }

    func quickLook(_ node: FileNode?) {
        guard let node, !node.isSynthetic else { return }
        previewURL = node.url
    }

    // MARK: - Duplicates

    var duplicateGroups: [DuplicateGroup]?
    var dupesLoading = false
    private var dupesCancel: CancelFlag?

    func findDuplicates() {
        guard let root, !dupesLoading else { return }
        dupesLoading = true
        // Collect candidate nodes on the main actor (tree access), hash off it.
        var candidates: [FileNode] = []
        root.walk { node in
            if !node.isDirectory && node.size >= DuplicateFinder.minSize {
                candidates.append(node)
            }
        }
        let flag = CancelFlag()
        dupesCancel = flag
        let snapshot = candidates
        Task.detached(priority: .userInitiated) { [vm = self] in
            let finder = DuplicateFinder(progress: nil, cancel: flag)
            let groups = (try? finder.find(files: snapshot)) ?? []
            await MainActor.run {
                vm.duplicateGroups = groups
                vm.dupesLoading = false
            }
        }
    }

    func cancelDuplicates() {
        dupesCancel?.cancel()
        dupesLoading = false
    }

    // MARK: - Scan history / diff

    var availableBaselines: [URL] = []
    var diffEntries: [DiffEntry]?
    var diffLoading = false
    var diffBaseline: URL? {
        didSet { loadDiff() }
    }

    func refreshBaselines() {
        guard let root else { availableBaselines = []; return }
        // Skip the snapshot just saved for the current scan — comparing a scan
        // with itself is always empty.
        availableBaselines = Array(ScanStore.list(forRootPath: root.url.path)
            .filter { $0 != lastSavedSnapshot }
            .prefix(ScanStore.keepPerRoot))
    }

    private var lastSavedSnapshot: URL?

    private func loadDiff() {
        guard let baseline = diffBaseline, let root else {
            diffEntries = nil
            return
        }
        diffLoading = true
        Task.detached(priority: .userInitiated) { [vm = self] in
            let entries: [DiffEntry]?
            if let old = try? ScanStore.load(baseline) {
                entries = ScanStore.diff(old: old, currentRoot: root)
            } else {
                entries = nil
            }
            await MainActor.run {
                vm.diffEntries = entries
                vm.diffLoading = false
            }
        }
    }

    // MARK: - Reclaimables

    var reclaimables: [ReclaimableResult] = []
    var snapshots: [TMSnapshot] = []
    var reclaimablesLoading = false
    var snapshotMessage: String?

    /// node_modules directories found in the current scan tree.
    var nodeModulesDirs: [FileNode] {
        _ = tick
        return root?.findDirectories(named: "node_modules") ?? []
    }

    func loadReclaimables() {
        guard !reclaimablesLoading else { return }
        reclaimablesLoading = true
        Task.detached(priority: .userInitiated) { [vm = self] in
            let results = ReclaimablesCatalog.measure()
            let snaps = SnapshotManager.list()
            await MainActor.run {
                vm.reclaimables = results
                vm.snapshots = snaps
                vm.reclaimablesLoading = false
            }
        }
    }

    func deleteSnapshot(_ snapshot: TMSnapshot) {
        guard let token = snapshot.deletableDate else { return }
        Task.detached(priority: .userInitiated) { [vm = self] in
            let output = SnapshotManager.delete(dateToken: token)
            let snaps = SnapshotManager.list()
            await MainActor.run {
                vm.snapshotMessage = output.trimmingCharacters(in: .whitespacesAndNewlines)
                vm.snapshots = snaps
            }
        }
    }

    // MARK: - Actions

    func reveal(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func moveToTrash(_ node: FileNode) {
        trash([node])
    }

    /// Move any number of nodes to the Trash; updates the tree, the reclaimed
    /// counter, and the collector, and reports per-item failures.
    func trash(_ nodes: [FileNode]) {
        var failures: [String] = []
        var trashedAny = false
        for node in nodes where !node.isSynthetic {
            do {
                try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
                reclaimedBytes += node.size
                trashedAny = true
                if selection === node {
                    selection = nil
                    tableSelection = nil
                }
                // If we were focused inside the deleted directory, pop out.
                if let index = path.firstIndex(where: { $0 === node }) {
                    path = Array(path[..<index])
                }
                collector.removeAll { node.isSelfOrAncestor(of: $0) }
                node.removeFromParent()
            } catch {
                failures.append("\(node.name): \(error.localizedDescription)")
            }
        }
        if trashedAny { tick += 1 }
        lastError = failures.isEmpty ? nil : "Couldn't move to Trash — " + failures.joined(separator: "; ")
    }

    // MARK: - Collector

    var collector: [FileNode] = []

    var collectorTotal: Int64 {
        _ = tick
        return collector.reduce(0) { $0 + $1.size }
    }

    func isInCollector(_ node: FileNode) -> Bool {
        collector.contains { $0 === node || $0.isSelfOrAncestor(of: node) }
    }

    func addToCollector(_ node: FileNode) {
        guard !node.isSynthetic, !isInCollector(node) else { return }
        // Adding an ancestor subsumes any collected descendants.
        collector.removeAll { node.isSelfOrAncestor(of: $0) }
        collector.append(node)
    }

    func removeFromCollector(_ node: FileNode) {
        collector.removeAll { $0 === node }
    }

    /// Trash everything in the collector. Successfully trashed items are
    /// removed by `trash`; failed ones stay in the basket.
    func emptyCollector() {
        trash(collector)
    }
}
