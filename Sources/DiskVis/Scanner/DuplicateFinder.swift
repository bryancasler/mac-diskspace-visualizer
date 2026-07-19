import CryptoKit
import Foundation

struct DuplicateGroup: Identifiable, Sendable {
    let id = UUID()
    let size: Int64
    /// Newest first; ≥ 2 entries.
    let files: [FileNode]
    var wastedBytes: Int64 { size * Int64(files.count - 1) }
}

/// Finds identical files: size grouping → partial hash → full SHA-256.
/// Hard links (same inode) are excluded — they already share storage.
/// APFS clones can't be detected from user space, so freed space can be less
/// than reported; the UI carries that caveat.
struct DuplicateFinder {
    var progress: ProgressBox?
    var cancel: CancelFlag?

    static let minSize: Int64 = 1_000_000
    private static let partialChunk = 65536

    func find(files candidates: [FileNode]) throws -> [DuplicateGroup] {
        // 1. Group by exact size
        var bySize: [Int64: [FileNode]] = [:]
        for file in candidates where file.size >= Self.minSize {
            bySize[file.size, default: []].append(file)
        }

        var groups: [DuplicateGroup] = []
        for (size, sameSize) in bySize where sameSize.count > 1 {
            if cancel?.isCancelled == true { throw CancellationError() }

            // 2. Drop hard links: one representative per (device, inode)
            var byInode: [String: FileNode] = [:]
            for file in sameSize {
                var st = stat()
                guard lstat(file.url.path, &st) == 0 else { continue }
                let key = "\(st.st_dev):\(st.st_ino)"
                if byInode[key] == nil { byInode[key] = file }
            }
            let unique = Array(byInode.values)
            guard unique.count > 1 else { continue }

            // 3. Partial hash (first + last 64 KB)
            var byPartial: [String: [FileNode]] = [:]
            for file in unique {
                guard let digest = hash(file.url, fullFile: false) else { continue }
                byPartial[digest, default: []].append(file)
            }

            // 4. Full hash only where partials collide
            for (_, partialMatch) in byPartial where partialMatch.count > 1 {
                var byFull: [String: [FileNode]] = [:]
                for file in partialMatch {
                    if cancel?.isCancelled == true { throw CancellationError() }
                    guard let digest = hash(file.url, fullFile: true) else { continue }
                    byFull[digest, default: []].append(file)
                    progress?.add(items: 1, bytes: file.size, path: file.url.path)
                }
                for (_, matches) in byFull where matches.count > 1 {
                    groups.append(DuplicateGroup(
                        size: size,
                        files: matches.sorted { $0.modified > $1.modified }
                    ))
                }
            }
        }
        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    private func hash(_ url: URL, fullFile: Bool) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            if fullFile {
                while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                    hasher.update(data: chunk)
                    if cancel?.isCancelled == true { return nil }
                }
            } else {
                if let head = try handle.read(upToCount: Self.partialChunk) {
                    hasher.update(data: head)
                }
                let size = try handle.seekToEnd()
                if size > Int64(Self.partialChunk * 2) {
                    try handle.seek(toOffset: size - UInt64(Self.partialChunk))
                    if let tail = try handle.read(upToCount: Self.partialChunk) {
                        hasher.update(data: tail)
                    }
                }
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
