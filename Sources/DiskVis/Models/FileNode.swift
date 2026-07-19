import Foundation

/// A node in the scanned file tree. Built on a background thread, then handed
/// to the main actor; after that, mutations (deletion) happen on main only.
final class FileNode: Identifiable, @unchecked Sendable {
    let id = UUID()
    let name: String
    let url: URL
    let isDirectory: Bool
    var size: Int64
    /// Last-modified time (seconds since epoch); 0 when unknown.
    var modified: Int64 = 0
    var isInaccessible = false
    /// True for aggregate "(N smaller items)" placeholder nodes.
    var isSynthetic = false
    private(set) var children: [FileNode] = []
    weak var parent: FileNode?

    init(name: String, url: URL, isDirectory: Bool, size: Int64 = 0) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.size = size
    }

    func setChildren(_ nodes: [FileNode]) {
        children = nodes.sorted { $0.size > $1.size }
        for child in children { child.parent = self }
    }

    /// Detach this node and subtract its size from every ancestor.
    func removeFromParent() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        var ancestor: FileNode? = parent
        while let node = ancestor {
            node.size -= size
            ancestor = node.parent
        }
        self.parent = nil
    }

    var fractionOfParent: Double {
        guard let parent, parent.size > 0 else { return 1 }
        return Double(size) / Double(parent.size)
    }

    // MARK: - Traversal

    /// Depth-first visit of every real (non-synthetic) descendant.
    func walk(_ visit: (FileNode) -> Void) {
        for child in children where !child.isSynthetic {
            visit(child)
            if child.isDirectory { child.walk(visit) }
        }
    }

    /// Largest files anywhere under this node, biggest first.
    /// `olderThan` filters to files not modified since that time.
    func collectFiles(limit: Int, minSize: Int64 = 1, olderThan: Int64? = nil) -> [FileNode] {
        var files: [FileNode] = []
        walk { node in
            guard !node.isDirectory, node.size >= minSize else { return }
            if let cutoff = olderThan, node.modified == 0 || node.modified > cutoff { return }
            files.append(node)
        }
        files.sort { $0.size > $1.size }
        return Array(files.prefix(limit))
    }

    /// Case-insensitive name-substring search over all descendants.
    func search(query: String, minSize: Int64 = 0, limit: Int = 500) -> [FileNode] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }
        var matches: [FileNode] = []
        walk { node in
            guard node.size >= minSize else { return }
            if node.name.lowercased().contains(needle) { matches.append(node) }
        }
        matches.sort { $0.size > $1.size }
        return Array(matches.prefix(limit))
    }

    /// Directories with the given name; does not descend into matches
    /// (so nested node_modules aren't double-counted).
    func findDirectories(named name: String) -> [FileNode] {
        var matches: [FileNode] = []
        func recurse(_ node: FileNode) {
            for child in node.children where child.isDirectory && !child.isSynthetic {
                if child.name == name {
                    matches.append(child)
                } else {
                    recurse(child)
                }
            }
        }
        recurse(self)
        return matches
    }

    /// True if `other` is this node or an ancestor of it.
    func isSelfOrAncestor(of other: FileNode) -> Bool {
        var node: FileNode? = other
        while let current = node {
            if current === self { return true }
            node = current.parent
        }
        return false
    }
}
