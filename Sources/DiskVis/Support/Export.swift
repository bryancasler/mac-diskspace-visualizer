import AppKit
import Foundation
import UniformTypeIdentifiers

/// Flat serializable representation of a scanned node, shared by export and
/// (later) the scan-history store.
struct FlatNode: Codable {
    let path: String
    let size: Int64
    let isDirectory: Bool
    let modified: Int64
}

enum Export {
    /// Files ≥ minSize plus all directories, largest first.
    static func flatten(_ root: FileNode, minFileSize: Int64 = 1_000_000) -> [FlatNode] {
        var nodes: [FlatNode] = [FlatNode(path: root.url.path, size: root.size, isDirectory: true, modified: 0)]
        root.walkIncludingCollapsed { node in
            guard node.isDirectory || node.size >= minFileSize else { return }
            nodes.append(FlatNode(
                path: node.url.path,
                size: node.size,
                isDirectory: node.isDirectory,
                modified: node.modified
            ))
        }
        nodes.sort { $0.size > $1.size }
        return nodes
    }

    static func csv(_ nodes: [FlatNode]) -> String {
        var out = "path,size_bytes,type,modified\n"
        for node in nodes {
            let escaped = node.path.contains(",") || node.path.contains("\"")
                ? "\"" + node.path.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                : node.path
            let modified = node.modified > 0
                ? ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(node.modified)))
                : ""
            out += "\(escaped),\(node.size),\(node.isDirectory ? "dir" : "file"),\(modified)\n"
        }
        return out
    }

    /// Only the save-panel interaction needs the main actor; the tree walk,
    /// encoding, and disk write are dispatched to a background task so a
    /// large scan's export doesn't freeze the UI.
    @MainActor
    static func save(root: FileNode, asCSV: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [asCSV ? .commaSeparatedText : .json]
        panel.nameFieldStringValue = "DiskVis-\(root.name).\(asCSV ? "csv" : "json")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task.detached(priority: .userInitiated) {
            do {
                try write(root: root, to: url, asCSV: asCSV)
            } catch {
                await MainActor.run { _ = NSAlert(error: error).runModal() }
            }
        }
    }

    private static func write(root: FileNode, to url: URL, asCSV: Bool) throws {
        let nodes = flatten(root)
        if asCSV {
            try csv(nodes).write(to: url, atomically: true, encoding: .utf8)
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(nodes).write(to: url)
        }
    }
}
