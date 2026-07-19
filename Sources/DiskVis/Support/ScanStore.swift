import CryptoKit
import Foundation

struct ScanSnapshot: Codable {
    let rootPath: String
    let date: Date
    let totalSize: Int64
    let nodes: [FlatNode]
}

struct DiffEntry: Identifiable {
    enum Kind { case grown, shrunk, added, removed }
    let id = UUID()
    let path: String
    let oldSize: Int64
    let newSize: Int64
    let kind: Kind
    var delta: Int64 { newSize - oldSize }
}

/// Persists compact per-scan snapshots and diffs them against a live tree.
enum ScanStore {
    static let keepPerRoot = 10
    /// Only files this large (or directories) are recorded.
    static let minFileSize: Int64 = 1_000_000

    static var baseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "DiskVis/scans")
    }

    private static func directory(forRootPath path: String) -> URL {
        let hash = SHA256.hash(data: Data(path.utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
        return baseDirectory.appending(path: hash)
    }

    // MARK: - Save / load

    @discardableResult
    static func save(root: FileNode) throws -> URL {
        let snapshot = ScanSnapshot(
            rootPath: root.url.path,
            date: Date(),
            totalSize: root.size,
            nodes: Export.flatten(root, minFileSize: minFileSize)
        )
        let dir = directory(forRootPath: root.url.path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withTimeZone]
        let name = formatter.string(from: snapshot.date)
            .replacingOccurrences(of: ":", with: "-") + ".json.z"
        let url = dir.appending(path: name)
        let data = try JSONEncoder().encode(snapshot)
        let compressed = try (data as NSData).compressed(using: .zlib)
        try (compressed as Data).write(to: url)
        prune(directory: dir)
        return url
    }

    static func list(forRootPath path: String) -> [URL] {
        let dir = directory(forRootPath: path)
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )) ?? []
        return items
            .filter { $0.lastPathComponent.hasSuffix(".json.z") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // newest first
    }

    static func load(_ url: URL) throws -> ScanSnapshot {
        let compressed = try Data(contentsOf: url)
        let data = try (compressed as NSData).decompressed(using: .zlib)
        return try JSONDecoder().decode(ScanSnapshot.self, from: data as Data)
    }

    private static func prune(directory: URL) {
        let items = ((try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? [])
            .filter { $0.lastPathComponent.hasSuffix(".json.z") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for stale in items.dropFirst(keepPerRoot) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    // MARK: - Diff

    /// File-level diff (directories excluded to avoid double counting),
    /// biggest absolute change first.
    static func diff(old: ScanSnapshot, currentRoot: FileNode) -> [DiffEntry] {
        var oldFiles: [String: Int64] = [:]
        for node in old.nodes where !node.isDirectory {
            oldFiles[node.path] = node.size
        }

        var entries: [DiffEntry] = []
        var seen = Set<String>()
        currentRoot.walk { node in
            guard !node.isDirectory, node.size >= minFileSize || oldFiles[node.url.path] != nil else { return }
            let path = node.url.path
            seen.insert(path)
            if let oldSize = oldFiles[path] {
                if node.size != oldSize {
                    entries.append(DiffEntry(
                        path: path, oldSize: oldSize, newSize: node.size,
                        kind: node.size > oldSize ? .grown : .shrunk
                    ))
                }
            } else if node.size >= minFileSize {
                entries.append(DiffEntry(path: path, oldSize: 0, newSize: node.size, kind: .added))
            }
        }
        for (path, oldSize) in oldFiles where !seen.contains(path) {
            entries.append(DiffEntry(path: path, oldSize: oldSize, newSize: 0, kind: .removed))
        }
        return entries.sorted { abs($0.delta) > abs($1.delta) }
    }
}
