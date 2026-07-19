import Foundation

/// Thread-safe progress counters shared between the scan thread and the UI.
final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _items = 0
    private var _bytes: Int64 = 0
    private var _currentPath = ""
    private var _inaccessible = 0

    func reset() {
        lock.lock(); defer { lock.unlock() }
        _items = 0; _bytes = 0; _currentPath = ""; _inaccessible = 0
    }

    func add(items: Int, bytes: Int64, path: String) {
        lock.lock(); defer { lock.unlock() }
        _items += items
        _bytes += bytes
        _currentPath = path
    }

    func noteInaccessible() {
        lock.lock(); defer { lock.unlock() }
        _inaccessible += 1
    }

    var snapshot: (items: Int, bytes: Int64, path: String, inaccessible: Int) {
        lock.lock(); defer { lock.unlock() }
        return (_items, _bytes, _currentPath, _inaccessible)
    }
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        _cancelled = true
    }
}

/// Scans a directory tree and reports *deduplicated allocated* sizes:
/// `lstat` block counts (the same accounting `du` uses), with files that have
/// multiple hard links counted only once per scan.
final class DiskScanner {
    private let progress: ProgressBox?
    private let cancel: CancelFlag?
    /// (device, inode) pairs of multi-link files already counted this scan.
    private var seenHardLinks = Set<HardLinkKey>()
    /// (device, inode) pairs of directories already scanned — guards against
    /// aliased views of the same tree (firmlinks, /.nofollow-style synthetics).
    private var seenDirectories = Set<HardLinkKey>()

    private struct HardLinkKey: Hashable {
        let device: Int32
        let inode: UInt64
    }

    init(progress: ProgressBox? = nil, cancel: CancelFlag? = nil) {
        self.progress = progress
        self.cancel = cancel
    }

    /// Directories that would double-count data (firmlinked volume mounts,
    /// kernel synthetic aliases of the root hierarchy) or are virtual/foreign
    /// when scanning the startup volume.
    static let skippedPaths: Set<String> = [
        "/System/Volumes",
        "/Volumes",
        "/dev",
        "/.nofollow",   // magic alias of the whole root tree (macOS 26)
        "/.resolve",    // file-ID path resolution alias
        "/.vol",        // legacy volfs alias
    ]

    /// Directories with more children than this get their smallest entries
    /// collapsed into a single synthetic node to keep the tree light.
    static let maxChildrenPerDirectory = 400

    func scan(url: URL) throws -> FileNode {
        let standardized = url.standardizedFileURL
        let name = standardized.path == "/" ? "Macintosh HD" : standardized.lastPathComponent
        let root = FileNode(name: name, url: standardized, isDirectory: true)
        seenHardLinks.removeAll(keepingCapacity: true)
        seenDirectories.removeAll(keepingCapacity: true)
        var rootStat = stat()
        if lstat(standardized.path, &rootStat) == 0 {
            seenDirectories.insert(HardLinkKey(device: rootStat.st_dev, inode: rootStat.st_ino))
        }
        try scanInto(root)
        return root
    }

    private func scanInto(_ node: FileNode) throws {
        if cancel?.isCancelled == true { throw CancellationError() }

        let dirPath = node.url.path
        let names: [String]
        do {
            // Sorted so traversal — and therefore hard-link winner selection
            // below — is deterministic across scans of an unchanged tree,
            // instead of depending on filesystem enumeration order.
            names = try FileManager.default.contentsOfDirectory(atPath: dirPath).sorted()
        } catch {
            node.isInaccessible = true
            progress?.noteInaccessible()
            return
        }

        var kids: [FileNode] = []
        kids.reserveCapacity(names.count)
        var total: Int64 = 0
        var fileBytes: Int64 = 0
        let prefix = dirPath == "/" ? "/" : dirPath + "/"

        for name in names {
            let path = prefix + name
            if Self.skippedPaths.contains(path) { continue }

            var st = stat()
            guard lstat(path, &st) == 0 else { continue }
            let type = st.st_mode & S_IFMT

            if type == S_IFDIR {
                // Each directory inode is scanned once per scan; aliased views
                // of an already-counted tree are skipped entirely.
                let key = HardLinkKey(device: st.st_dev, inode: st.st_ino)
                guard seenDirectories.insert(key).inserted else { continue }
                let child = FileNode(name: name, url: URL(fileURLWithPath: path, isDirectory: true), isDirectory: true)
                try scanInto(child)
                kids.append(child)
                total += child.size
            } else {
                // Allocated blocks — the same accounting `du` uses. Handles
                // sparse, compressed, and dataless (cloud placeholder) files.
                var size = Int64(st.st_blocks) * 512
                if type == S_IFREG, st.st_nlink > 1 {
                    // Hard links: count the underlying inode once per scan.
                    let key = HardLinkKey(device: st.st_dev, inode: st.st_ino)
                    if !seenHardLinks.insert(key).inserted { size = 0 }
                }
                let child = FileNode(name: name, url: URL(fileURLWithPath: path), isDirectory: false, size: size)
                child.modified = Int64(st.st_mtimespec.tv_sec)
                kids.append(child)
                total += size
                fileBytes += size
            }
        }

        progress?.add(items: names.count, bytes: fileBytes, path: dirPath)

        if kids.count > Self.maxChildrenPerDirectory {
            kids.sort { $0.size > $1.size }
            let keep = Array(kids.prefix(Self.maxChildrenPerDirectory - 1))
            let rest = kids.dropFirst(Self.maxChildrenPerDirectory - 1)
            let restSize = rest.reduce(Int64(0)) { $0 + $1.size }
            let synthetic = FileNode(
                name: "(\(rest.count) smaller items)",
                url: node.url,
                isDirectory: false,
                size: restSize
            )
            synthetic.isSynthetic = true
            // Preserve the collapsed originals as children (instead of
            // discarding them) so scan-history diffing can still see them
            // via walkIncludingCollapsed — UI traversal (walk) still treats
            // this node as an opaque leaf since isDirectory is false.
            synthetic.setChildren(Array(rest))
            kids = keep + [synthetic]
        }

        node.size = total
        node.setChildren(kids)
    }
}
