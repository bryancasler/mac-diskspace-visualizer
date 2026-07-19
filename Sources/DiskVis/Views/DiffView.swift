import SwiftUI

/// Right-pane mode: what changed since a previous scan of the same root.
struct DiffView: View {
    @Environment(ScanViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            HStack {
                Text("Compare with:")
                    .foregroundStyle(.secondary)
                Picker("Baseline", selection: $vm.diffBaseline) {
                    Text("None").tag(URL?.none)
                    ForEach(vm.availableBaselines, id: \.self) { url in
                        Text(Self.label(for: url)).tag(URL?.some(url))
                    }
                }
                .labelsHidden()
                Spacer()
                if vm.diffLoading { ProgressView().controlSize(.small) }
            }
            .padding(10)

            Divider()

            if vm.availableBaselines.isEmpty {
                ContentUnavailableView(
                    "No earlier scans yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Every completed scan is saved automatically. Rescan this folder later and the changes will show up here.")
                )
            } else if let entries = vm.diffEntries {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No changes",
                        systemImage: "equal.circle",
                        description: Text("Nothing over \(Format.bytes(ScanStore.minFileSize)) changed since that scan.")
                    )
                } else {
                    Table(entries) {
                        TableColumn("File") { entry in
                            Text(relativePath(entry.path))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(entry.path)
                        }
                        .width(min: 180, ideal: 280)

                        TableColumn("Change") { entry in
                            HStack(spacing: 4) {
                                Image(systemName: symbol(for: entry.kind))
                                    .foregroundStyle(color(for: entry.kind))
                                Text(changeText(entry))
                                    .foregroundStyle(color(for: entry.kind))
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .width(min: 110, ideal: 140)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Pick a baseline",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Choose an earlier scan above to see what grew or shrank.")
                )
            }
        }
        .onAppear { vm.refreshBaselines() }
    }

    private static func label(for url: URL) -> String {
        // 2026-07-18T20-15-00Z.json.z → readable date
        let stem = url.lastPathComponent.replacingOccurrences(of: ".json.z", with: "")
        guard let tIndex = stem.range(of: "T") else { return stem }
        let restored = stem[..<tIndex.lowerBound] + stem[tIndex.lowerBound...]
            .replacingOccurrences(of: "-", with: ":")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withTimeZone]
        if let date = formatter.date(from: String(restored)) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return stem
    }

    private func relativePath(_ path: String) -> String {
        guard let rootPath = vm.root?.url.path, path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func symbol(for kind: DiffEntry.Kind) -> String {
        switch kind {
        case .grown: "arrow.up.circle.fill"
        case .shrunk: "arrow.down.circle.fill"
        case .added: "plus.circle.fill"
        case .removed: "minus.circle.fill"
        }
    }

    private func color(for kind: DiffEntry.Kind) -> Color {
        switch kind {
        case .grown, .added: .red      // grew = costing you space
        case .shrunk, .removed: .green // shrank = space came back
        }
    }

    private func changeText(_ entry: DiffEntry) -> String {
        switch entry.kind {
        case .added: "+\(Format.bytes(entry.newSize)) new"
        case .removed: "−\(Format.bytes(entry.oldSize)) gone"
        case .grown: "+\(Format.bytes(entry.delta))"
        case .shrunk: "−\(Format.bytes(-entry.delta))"
        }
    }
}
