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
    }
}
