import AppKit
import SwiftUI

@main
struct DiskVisApp: App {
    @State private var vm = ScanViewModel()
    @State private var watcher = FreeSpaceWatcher()
    @AppStorage("menuBarEnabled") private var menuBarEnabled = true

    init() {
        Self.runHeadlessScanIfRequested()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(vm)
                .onAppear {
                    // Behave like a regular app even when launched as a bare
                    // executable during development.
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .importExport) {
                Button("Export Scan as CSV…") {
                    if let root = vm.root { Export.save(root: root, asCSV: true) }
                }
                .disabled(vm.root == nil)
                Button("Export Scan as JSON…") {
                    if let root = vm.root { Export.save(root: root, asCSV: false) }
                }
                .disabled(vm.root == nil)
            }
        }

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarView(watcher: watcher)
        } label: {
            Label(menuBarLabel, systemImage: "internaldrive")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }

    private var menuBarLabel: String {
        let free = watcher.startupFree
        return free > 0 ? Format.bytes(free) : "DiskVis"
    }

    /// `DiskVis --scan <path>` scans headlessly and prints results — used for
    /// verifying scanner correctness against `du` without launching the UI.
    /// `DiskVis --snapshot <path> <out.png>` additionally renders the sunburst
    /// for that path to a PNG (offscreen, no screen-capture permission needed).
    private static func runHeadlessScanIfRequested() {
        let args = CommandLine.arguments
        if let flagIndex = args.firstIndex(of: "--scan"), args.count > flagIndex + 1 {
            let url = URL(fileURLWithPath: args[flagIndex + 1])
            let progress = ProgressBox()
            do {
                let root = try DiskScanner(progress: progress, cancel: nil).scan(url: url)
                let snap = progress.snapshot
                print("TOTAL\t\(root.size)\t\(Format.bytes(root.size))")
                print("ITEMS\t\(snap.items)\tINACCESSIBLE\t\(snap.inaccessible)")
                for child in root.children.prefix(15) {
                    print("  \(child.size)\t\(Format.bytes(child.size))\t\(child.name)\(child.isDirectory ? "/" : "")")
                }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("scan failed: \(error)\n".utf8))
                exit(1)
            }
        }
        // `DiskVis --files <path> [--older-days N]` prints the largest files
        // under <path>, optionally only those not modified in N days.
        if let flagIndex = args.firstIndex(of: "--files"), args.count > flagIndex + 1 {
            let url = URL(fileURLWithPath: args[flagIndex + 1])
            var olderThan: Int64?
            if let daysIndex = args.firstIndex(of: "--older-days"), args.count > daysIndex + 1,
               let days = Int64(args[daysIndex + 1]) {
                olderThan = Int64(Date().timeIntervalSince1970) - days * 86400
            }
            do {
                let root = try DiskScanner().scan(url: url)
                for file in root.collectFiles(limit: 20, olderThan: olderThan) {
                    print("\(file.size)\t\(Format.date(file.modified))\t\(file.url.path)")
                }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("files failed: \(error)\n".utf8))
                exit(1)
            }
        }
        // `DiskVis --dupes <path>` finds duplicate files under <path>.
        if let flagIndex = args.firstIndex(of: "--dupes"), args.count > flagIndex + 1 {
            let url = URL(fileURLWithPath: args[flagIndex + 1])
            do {
                let root = try DiskScanner().scan(url: url)
                var candidates: [FileNode] = []
                root.walk { if !$0.isDirectory && $0.size >= DuplicateFinder.minSize { candidates.append($0) } }
                let groups = try DuplicateFinder().find(files: candidates)
                print("\(groups.count) groups")
                for group in groups {
                    print("GROUP \(group.files.count) x \(group.size) wastes \(group.wastedBytes)")
                    for file in group.files { print("  \(file.url.path)") }
                }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("dupes failed: \(error)\n".utf8))
                exit(1)
            }
        }
        // `DiskVis --save-snapshot <path>` scans and stores a history snapshot.
        // `DiskVis --diff <path>` scans and diffs against the latest snapshot.
        if let flagIndex = args.firstIndex(of: "--save-snapshot"), args.count > flagIndex + 1 {
            let url = URL(fileURLWithPath: args[flagIndex + 1])
            do {
                let root = try DiskScanner().scan(url: url)
                let saved = try ScanStore.save(root: root)
                print("saved \(saved.path)")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("save failed: \(error)\n".utf8))
                exit(1)
            }
        }
        if let flagIndex = args.firstIndex(of: "--diff"), args.count > flagIndex + 1 {
            let url = URL(fileURLWithPath: args[flagIndex + 1])
            do {
                let root = try DiskScanner().scan(url: url)
                guard let baseline = ScanStore.list(forRootPath: root.url.path).first else {
                    print("no baseline snapshot for \(root.url.path)"); exit(1)
                }
                let old = try ScanStore.load(baseline)
                for entry in ScanStore.diff(old: old, currentRoot: root).prefix(15) {
                    print("\(entry.kind)\t\(entry.oldSize) -> \(entry.newSize)\t\(entry.path)")
                }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("diff failed: \(error)\n".utf8))
                exit(1)
            }
        }
        // `DiskVis --reclaimables` prints measured catalog sizes (read-only).
        if args.contains("--reclaimables") {
            for result in ReclaimablesCatalog.measure() {
                let safety = result.category.safety == .safe ? "SAFE" : "CAUTION"
                print("\(result.totalSize)\t\(Format.bytes(result.totalSize))\t\(safety)\t\(result.category.title)")
            }
            exit(0)
        }
        // `DiskVis --snapshots` prints parsed local snapshots (read-only).
        if args.contains("--snapshots") {
            for snapshot in SnapshotManager.list() {
                print("\(snapshot.deletableDate ?? "-")\t\(snapshot.isOSUpdate ? "os-update" : "tm")\t\(snapshot.name)")
            }
            exit(0)
        }
        // `DiskVis --trash-test <path>` scans <path>, batch-trashes its two
        // largest top-level files via the view model, and verifies tree totals
        // and the reclaimed counter. Only for throwaway fixture directories.
        if let flagIndex = args.firstIndex(of: "--trash-test"), args.count > flagIndex + 1 {
            let url = URL(fileURLWithPath: args[flagIndex + 1])
            do {
                let root = try DiskScanner().scan(url: url)
                let victims = Array(root.children.filter { !$0.isDirectory && !$0.isSynthetic }.prefix(2))
                guard !victims.isEmpty else { print("no file children to trash"); exit(1) }
                let before = root.size
                let victimTotal = victims.reduce(Int64(0)) { $0 + $1.size }
                MainActor.assumeIsolated {
                    let vm = ScanViewModel()
                    vm.root = root
                    vm.path = [root]
                    vm.trash(victims)
                    print("trashed\t\(victims.map(\.name).joined(separator: ", "))\t\(victimTotal)")
                    print("root before\t\(before)\tafter\t\(root.size)\tdelta ok\t\(before - root.size == victimTotal)")
                    print("reclaimed counter ok\t\(vm.reclaimedBytes == victimTotal)")
                    print("errors\t\(vm.lastError ?? "none")")
                }
                let rescanned = try DiskScanner().scan(url: url)
                print("rescan agrees\t\(rescanned.size == root.size)")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("trash test failed: \(error)\n".utf8))
                exit(1)
            }
        }
        if let flagIndex = args.firstIndex(of: "--snapshot"), args.count > flagIndex + 2 {
            let url = URL(fileURLWithPath: args[flagIndex + 1])
            let output = URL(fileURLWithPath: args[flagIndex + 2])
            let wantsTreemap = args.contains("--view") &&
                args.firstIndex(of: "--view").map { args.count > $0 + 1 && args[$0 + 1] == "treemap" } == true
            do {
                let root = try DiskScanner().scan(url: url)
                try MainActor.assumeIsolated {
                    let chart: AnyView = wantsTreemap
                        ? AnyView(TreemapView(
                            center: root, tick: 0, selection: nil,
                            onSelect: { _ in }, onDrill: { _ in }, onUp: {}
                        ))
                        : AnyView(SunburstView(
                            center: root, tick: 0, selection: nil,
                            onSelect: { _ in }, onDrill: { _ in }, onUp: {}
                        ))
                    let view = chart
                        .frame(width: 900, height: 700)
                        .background(Color(nsColor: .windowBackgroundColor))
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    guard let cgImage = renderer.cgImage else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    let rep = NSBitmapImageRep(cgImage: cgImage)
                    guard let png = rep.representation(using: .png, properties: [:]) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    try png.write(to: output)
                }
                print("snapshot written to \(output.path)")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
                exit(1)
            }
        }
        // `DiskVis --selftest` asserts pure in-memory FileNode tree logic
        // (no scanning, no disk I/O) — for mechanisms that don't need real
        // files to verify, like the synthetic-node traversal used by
        // scan-history diffing and the Reclaimables live-tree lookup.
        if args.contains("--selftest") {
            var failures = 0
            func check(_ name: String, _ pass: Bool) {
                print("\(pass ? "PASS" : "FAIL")\t\(name)")
                if !pass { failures += 1 }
            }

            // Build: /fake/dir/{fileA, fileB, synthetic{fileC, fileD}} — the
            // synthetic node reuses its enclosing directory's URL, and the
            // files it collapsed keep their true original paths, exactly
            // matching what DiskScanner actually constructs.
            func node(_ path: String, dir: Bool, size: Int64) -> FileNode {
                FileNode(name: (path as NSString).lastPathComponent, url: URL(fileURLWithPath: path), isDirectory: dir, size: size)
            }
            let root = node("/fake", dir: true, size: 0)
            let subdir = node("/fake/dir", dir: true, size: 0)
            let fileA = node("/fake/dir/fileA", dir: false, size: 10)
            let fileB = node("/fake/dir/fileB", dir: false, size: 20)
            let fileC = node("/fake/dir/fileC", dir: false, size: 5)
            let fileD = node("/fake/dir/fileD", dir: false, size: 3)
            // Matches DiskScanner: the synthetic node reuses its enclosing
            // directory's URL but gets its own distinct display name.
            let synthetic = FileNode(name: "(2 smaller items)", url: subdir.url, isDirectory: false, size: 8)
            synthetic.isSynthetic = true
            synthetic.setChildren([fileC, fileD])
            subdir.setChildren([fileA, fileB, synthetic])
            root.setChildren([subdir])

            var walked: [String] = []
            root.walk { walked.append($0.name) }
            check("walk() skips synthetic node and its children",
                  Set(walked) == ["dir", "fileA", "fileB"])

            var walkedAll: [String] = []
            root.walkIncludingCollapsed { walkedAll.append($0.name) }
            check("walkIncludingCollapsed() reaches collapsed children, skips the synthetic node itself",
                  Set(walkedAll) == ["dir", "fileA", "fileB", "fileC", "fileD"])

            check("find(atPath:) locates a real descendant by exact path",
                  root.find(atPath: fileA.url.path) === fileA)
            check("find(atPath:) returns nil for a path outside the tree",
                  root.find(atPath: "/fake/nonexistent") == nil)
            check("find(atPath:) does not descend into synthetic nodes",
                  root.find(atPath: fileC.url.path) == nil)

            // Reclaimables live-tree reconnection: a category path inside
            // the current scan root should resolve to the SAME object
            // (===) DiskScanner already produced, not a fresh standalone
            // scan — otherwise trashing it can't propagate back to the tree.
            let tmp = FileManager.default.temporaryDirectory.appending(path: "diskvis-selftest-\(UUID().uuidString)")
            do {
                let cacheDir = tmp.appending(path: "cache")
                try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                try Data(repeating: 0, count: 4096).write(to: cacheDir.appending(path: "blob.bin"))
                let scanned = try DiskScanner().scan(url: tmp)
                let inTreeCategory = ReclaimableCategory(
                    id: "t1", title: "t", explanation: "", safety: .safe, paths: [cacheDir.path]
                )
                let outOfTreeCategory = ReclaimableCategory(
                    id: "t2", title: "t", explanation: "", safety: .safe, paths: ["/private/etc"]
                )
                let inTreeResult = ReclaimablesCatalog.measure(categories: [inTreeCategory], root: scanned)
                check("measure(root:) reuses the live tree node for a covered path",
                      inTreeResult.first?.nodes.first === scanned.find(atPath: cacheDir.path))
                let outOfTreeResult = ReclaimablesCatalog.measure(categories: [outOfTreeCategory], root: scanned)
                check("measure(root:) falls back to a standalone scan outside the tree",
                      outOfTreeResult.first?.nodes.first != nil)
                try? FileManager.default.removeItem(at: tmp)
            } catch {
                check("Reclaimables reconnection fixture setup", false)
                try? FileManager.default.removeItem(at: tmp)
            }

            print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
            exit(failures == 0 ? 0 : 1)
        }
        // `DiskVis --ui-audit <fixture> <out-dir>` scans <fixture> and
        // renders every major screen offscreen (populated with realistic
        // state) to PNGs in <out-dir> — for visual UI/UX review without
        // needing interactive access to the running app.
        if let flagIndex = args.firstIndex(of: "--ui-audit"), args.count > flagIndex + 2 {
            let fixture = URL(fileURLWithPath: args[flagIndex + 1])
            let outDir = URL(fileURLWithPath: args[flagIndex + 2])
            do {
                try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
                let root = try DiskScanner().scan(url: fixture)
                try MainActor.assumeIsolated {
                    @MainActor
                    // Table/List/Form are AppKit-hosted and don't rasterize
                    // via plain ImageRenderer with no real window behind
                    // them (renders as a placeholder glyph) — host in an
                    // actual NSWindow and capture via cacheDisplay instead.
                    func snap<V: View>(_ name: String, width: CGFloat, height: CGFloat, @ViewBuilder _ content: () -> V) throws {
                        let view = content()
                            .frame(width: width, height: height)
                            .background(Color(nsColor: .windowBackgroundColor))
                        let hosting = NSHostingView(rootView: view)
                        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)

                        let window = NSWindow(
                            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                            styleMask: [.titled, .borderless],
                            backing: .buffered,
                            defer: false
                        )
                        window.contentView = hosting
                        window.setFrameOrigin(NSPoint(x: 40, y: 40))
                        window.orderFrontRegardless()
                        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

                        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                            throw CocoaError(.fileWriteUnknown)
                        }
                        rep.size = hosting.bounds.size
                        hosting.cacheDisplay(in: hosting.bounds, to: rep)
                        guard let png = rep.representation(using: .png, properties: [:]) else {
                            throw CocoaError(.fileWriteUnknown)
                        }
                        try png.write(to: outDir.appending(path: "\(name).png"))
                        window.close()
                        print("wrote \(name).png")
                    }

                    @MainActor
                    func makeVM(paneMode: ScanViewModel.PaneMode = .contents) -> ScanViewModel {
                        let vm = ScanViewModel()
                        vm.root = root
                        vm.path = [root]
                        vm.phase = .done
                        vm.paneMode = paneMode
                        vm.reclaimedBytes = 3_400_000_000
                        vm.volumeUsedBytes = root.size + 6_000_000_000
                        return vm
                    }

                    // 1. Welcome screen
                    try snap("01-welcome", width: 900, height: 620) {
                        WelcomeView().environment(ScanViewModel())
                    }

                    // 2. Scanning progress
                    try snap("02-scanning", width: 900, height: 620) {
                        let vm = ScanViewModel()
                        vm.phase = .scanning
                        vm.scannedItems = 48213
                        vm.scannedBytes = 18_400_000_000
                        vm.scanningPath = fixture.appending(path: "Library/Application Support/SomeApp").path
                        return ScanningView().environment(vm)
                    }

                    // 3. Main window — sunburst, Contents pane
                    try snap("03-main-sunburst-contents", width: 1100, height: 720) {
                        let vm = makeVM(paneMode: .contents)
                        vm.select(root.children.first)
                        return MainView().environment(vm)
                    }

                    // 4. Main window — treemap
                    try snap("04-main-treemap", width: 1100, height: 720) {
                        MainView().environment(makeVM())
                    }

                    // 5. Files pane (largest files)
                    try snap("05-main-files-pane", width: 1100, height: 720) {
                        MainView().environment(makeVM(paneMode: .files))
                    }

                    // 6. Duplicates pane, populated
                    try snap("06-main-duplicates", width: 1100, height: 720) {
                        let vm = makeVM(paneMode: .duplicates)
                        let files = root.collectFiles(limit: 6, minSize: 1)
                        if files.count >= 4 {
                            vm.duplicateGroups = [
                                DuplicateGroup(size: files[0].size, files: [files[0], files[1]]),
                                DuplicateGroup(size: files[2].size, files: [files[2], files[3], files[3]]),
                            ]
                        }
                        return MainView().environment(vm)
                    }

                    // 7. Changes (diff) pane, populated
                    try snap("07-main-changes", width: 1100, height: 720) {
                        let vm = makeVM(paneMode: .changes)
                        let files = root.collectFiles(limit: 6, minSize: 1)
                        if files.count >= 3 {
                            vm.diffEntries = [
                                DiffEntry(path: files[0].url.path, oldSize: files[0].size / 2, newSize: files[0].size, kind: .grown),
                                DiffEntry(path: files[1].url.path, oldSize: files[1].size * 2, newSize: files[1].size, kind: .shrunk),
                                DiffEntry(path: files[2].url.path, oldSize: 0, newSize: files[2].size, kind: .added),
                                DiffEntry(path: "/Users/example/Downloads/old-installer.dmg", oldSize: 850_000_000, newSize: 0, kind: .removed),
                            ]
                        }
                        return MainView().environment(vm)
                    }

                    // 8. Collector, empty state
                    try snap("08-collector-empty", width: 300, height: 560) {
                        CollectorView().environment(makeVM())
                    }

                    // 9. Collector, populated
                    try snap("09-collector-populated", width: 300, height: 560) {
                        let vm = makeVM()
                        vm.collector = Array(root.collectFiles(limit: 5, minSize: 1))
                        return CollectorView().environment(vm)
                    }

                    // 10. Reclaimables sheet
                    try snap("10-reclaimables", width: 720, height: 520) {
                        let vm = makeVM()
                        let categories = ReclaimablesCatalog.standard()
                        vm.reclaimables = [
                            ReclaimableResult(category: categories[0], nodes: [root]),
                            ReclaimableResult(category: categories[2], nodes: [root]),
                            ReclaimableResult(category: categories[15], nodes: [root]),
                        ]
                        vm.snapshots = [
                            TMSnapshot(name: "com.apple.TimeMachine.2026-07-10-093000.local", deletableDate: "2026-07-10-093000"),
                            TMSnapshot(name: "com.apple.os.update-ABCDEF", deletableDate: nil),
                        ]
                        return ReclaimablesView().environment(vm)
                    }

                    // 11. Settings
                    try snap("11-settings", width: 420, height: 220) {
                        SettingsView()
                    }
                }
                print("ui-audit complete")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("ui-audit failed: \(error)\n".utf8))
                exit(1)
            }
        }
    }
}
