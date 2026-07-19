import Foundation

/// A known space-hog location with guidance on how safe it is to delete.
struct ReclaimableCategory: Identifiable, Sendable {
    enum Safety: Sendable {
        case safe      // regenerated automatically; deleting costs a rebuild/redownload
        case caution   // deleting loses something you might want (backups, models)
    }

    let id: String
    let title: String
    let explanation: String
    let safety: Safety
    /// Absolute paths (already tilde-expanded); only existing ones are sized.
    let paths: [String]
}

/// Result of sizing one category: the existing paths as standalone FileNodes.
struct ReclaimableResult: Identifiable, Sendable {
    let category: ReclaimableCategory
    let nodes: [FileNode]
    var id: String { category.id }
    var totalSize: Int64 { nodes.reduce(0) { $0 + $1.size } }
}

enum ReclaimablesCatalog {
    static func standard() -> [ReclaimableCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func h(_ sub: String) -> String { home + "/" + sub }

        return [
            ReclaimableCategory(
                id: "derived-data", title: "Xcode DerivedData",
                explanation: "Build products and indexes. Xcode regenerates them on the next build.",
                safety: .safe, paths: [h("Library/Developer/Xcode/DerivedData")]
            ),
            ReclaimableCategory(
                id: "device-support", title: "Xcode Device Support",
                explanation: "Debug symbols for iOS/watchOS versions you've connected. Re-created when you plug a device in again.",
                safety: .safe,
                paths: [h("Library/Developer/Xcode/iOS DeviceSupport"),
                        h("Library/Developer/Xcode/watchOS DeviceSupport"),
                        h("Library/Developer/Xcode/tvOS DeviceSupport")]
            ),
            ReclaimableCategory(
                id: "xcode-archives", title: "Xcode Archives",
                explanation: "App archives from Product → Archive. Needed to re-symbolicate old crash logs or re-export past builds.",
                safety: .caution, paths: [h("Library/Developer/Xcode/Archives")]
            ),
            ReclaimableCategory(
                id: "simulators", title: "iOS Simulators",
                explanation: "Simulator runtimes and device data. Re-downloadable from Xcode, but they're large downloads.",
                safety: .caution, paths: [h("Library/Developer/CoreSimulator")]
            ),
            ReclaimableCategory(
                id: "npm-cache", title: "npm cache",
                explanation: "Package tarball cache. npm re-downloads what projects need.",
                safety: .safe, paths: [h(".npm")]
            ),
            ReclaimableCategory(
                id: "pnpm-store", title: "pnpm store",
                explanation: "Content-addressed package store. Existing node_modules keep working; pnpm re-downloads on demand.",
                safety: .safe, paths: [h("Library/pnpm/store"), h(".pnpm-store")]
            ),
            ReclaimableCategory(
                id: "yarn-cache", title: "Yarn cache",
                explanation: "Package cache. Yarn re-downloads what projects need.",
                safety: .safe, paths: [h("Library/Caches/Yarn"), h(".yarn/berry/cache")]
            ),
            ReclaimableCategory(
                id: "homebrew-cache", title: "Homebrew cache",
                explanation: "Downloaded bottles and sources. `brew` re-downloads as needed (or run `brew cleanup`).",
                safety: .safe, paths: [h("Library/Caches/Homebrew")]
            ),
            ReclaimableCategory(
                id: "pip-cache", title: "pip cache",
                explanation: "Python package cache. pip re-downloads as needed.",
                safety: .safe, paths: [h("Library/Caches/pip")]
            ),
            ReclaimableCategory(
                id: "cargo-registry", title: "Cargo registry",
                explanation: "Rust crate downloads and indexes. cargo re-fetches on the next build.",
                safety: .safe, paths: [h(".cargo/registry")]
            ),
            ReclaimableCategory(
                id: "go-mod", title: "Go module cache",
                explanation: "Downloaded Go modules. Note: files are read-only; clear with `go clean -modcache` if trashing fails.",
                safety: .safe, paths: [h("go/pkg/mod")]
            ),
            ReclaimableCategory(
                id: "lmstudio", title: "LM Studio models",
                explanation: "Local LLM weights. Deleting means re-downloading multi-GB models to use them again.",
                safety: .caution, paths: [h(".lmstudio")]
            ),
            ReclaimableCategory(
                id: "ollama", title: "Ollama models",
                explanation: "Local LLM weights. Re-downloadable with `ollama pull`, but large.",
                safety: .caution, paths: [h(".ollama/models")]
            ),
            ReclaimableCategory(
                id: "docker", title: "Docker Desktop data",
                explanation: "All images, containers, and volumes live in one disk file. Prefer `docker system prune` inside Docker; trashing this deletes everything Docker knows.",
                safety: .caution, paths: [h("Library/Containers/com.docker.docker/Data")]
            ),
            ReclaimableCategory(
                id: "browser-caches", title: "Browser caches",
                explanation: "Chrome/Firefox page caches. Rebuilt as you browse; you stay logged in.",
                safety: .safe,
                paths: [h("Library/Caches/Google/Chrome"), h("Library/Caches/Firefox")]
            ),
            ReclaimableCategory(
                id: "user-caches", title: "App caches (~/Library/Caches)",
                explanation: "All per-app caches. Apps rebuild what they need, but first launches get slower and a few apps keep real data here — skim the contents first.",
                safety: .caution, paths: [h("Library/Caches")]
            ),
            ReclaimableCategory(
                id: "ios-backups", title: "iPhone/iPad backups",
                explanation: "Local device backups from Finder sync. Deleting removes your ability to restore from them.",
                safety: .caution, paths: [h("Library/Application Support/MobileSync/Backup")]
            ),
            ReclaimableCategory(
                id: "trash", title: "Trash",
                explanation: "Already deleted, still occupying disk. Empty it from Finder when you're sure.",
                safety: .caution, paths: [h(".Trash")]
            ),
        ]
    }

    /// Size every existing catalog path. Runs full (small) scans; call off-main.
    static func measure(
        categories: [ReclaimableCategory] = standard(),
        cancel: CancelFlag? = nil
    ) -> [ReclaimableResult] {
        var results: [ReclaimableResult] = []
        for category in categories {
            var nodes: [FileNode] = []
            for path in category.paths where FileManager.default.fileExists(atPath: path) {
                if cancel?.isCancelled == true { return results }
                let scanner = DiskScanner(cancel: cancel)
                if let node = try? scanner.scan(url: URL(fileURLWithPath: path)) {
                    nodes.append(node)
                }
            }
            if !nodes.isEmpty {
                results.append(ReclaimableResult(category: category, nodes: nodes))
            }
        }
        return results.sorted { $0.totalSize > $1.totalSize }
    }
}

// MARK: - Time Machine local snapshots

struct TMSnapshot: Identifiable, Sendable {
    let name: String
    /// The date token tmutil needs for deletion (e.g. "2026-07-18-093000"),
    /// present only for com.apple.TimeMachine.* snapshots.
    let deletableDate: String?
    var id: String { name }

    var isOSUpdate: Bool { name.hasPrefix("com.apple.os.update") }
}

enum SnapshotManager {
    static func list() -> [TMSnapshot] {
        guard let output = run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]).output else { return [] }
        return output.split(separator: "\n")
            .map(String.init)
            .filter { !$0.hasPrefix("Snapshots for") && !$0.isEmpty }
            .map { name in
                var date: String?
                if name.hasPrefix("com.apple.TimeMachine.") {
                    // com.apple.TimeMachine.2026-07-18-093000.local → 2026-07-18-093000
                    let token = name
                        .replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
                        .replacingOccurrences(of: ".local", with: "")
                    date = token
                }
                return TMSnapshot(name: name, deletableDate: date)
            }
    }

    /// Delete one Time Machine snapshot by its date token.
    /// Returns tmutil's combined output for surfacing in the UI.
    static func delete(dateToken: String) -> String {
        let result = run("/usr/bin/tmutil", ["deletelocalsnapshots", dateToken])
        return result.output ?? "tmutil exited with status \(result.status)"
    }

    private static func run(_ launchPath: String, _ arguments: [String]) -> (output: String?, status: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (String(data: data, encoding: .utf8), process.terminationStatus)
        } catch {
            return (nil, -1)
        }
    }
}
