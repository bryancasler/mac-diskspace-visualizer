import Foundation

struct VolumeInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let url: URL
    let total: Int64
    let free: Int64
    var used: Int64 { max(0, total - free) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func mounted() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let total = values.volumeTotalCapacity, total > 0
            else { return nil }
            return VolumeInfo(
                id: url.path,
                name: values.volumeName ?? url.lastPathComponent,
                url: url,
                total: Int64(total),
                free: values.volumeAvailableCapacityForImportantUsage ?? 0
            )
        }
    }
}
