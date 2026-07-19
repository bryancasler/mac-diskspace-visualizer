import AppKit
import SwiftUI

/// Flat file table: largest files (with age filter) or search results.
struct FilesPane: View {
    @Environment(ScanViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        let rows = vm.filesPaneRows

        VStack(spacing: 0) {
            HStack {
                Picker("Scope", selection: $vm.filesScope) {
                    ForEach(ScanViewModel.FilesScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer()

                Picker("Age", selection: $vm.ageFilter) {
                    ForEach(ScanViewModel.AgeFilter.allCases) { age in
                        Text(age.rawValue).tag(age)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help("Only show files not modified in this long — old and big is the safest to delete")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if !vm.searchQuery.isEmpty {
                Text("\(rows.count) results for “\(vm.searchQuery)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }

            Table(rows, selection: $vm.tableSelection) {
                TableColumn("Name") { node in
                    HStack(spacing: 6) {
                        NodeIcon(node: node)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(node.name).lineLimit(1)
                            Text(location(of: node))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .width(min: 200, ideal: 300, max: 420)

                TableColumn("Size") { node in
                    Text(Format.bytes(node.size))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 70, ideal: 90, max: 120)

                TableColumn("Modified") { node in
                    Text(Format.date(node.modified))
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 100, max: 140)
            }
            .contextMenu(forSelectionType: FileNode.ID.self) { ids in
                if let node = node(for: ids.first, in: rows) {
                    Button("Show in Folder") { vm.focus(on: node) }
                    Button("Quick Look") { vm.quickLook(node) }
                    Button("Reveal in Finder") { vm.reveal(node) }
                    Divider()
                    Button("Add to Collector") { vm.addToCollector(node) }
                        .disabled(vm.isInCollector(node))
                    Button("Move to Trash", role: .destructive) { vm.requestTrash([node]) }
                }
            } primaryAction: { ids in
                if let node = node(for: ids.first, in: rows) { vm.focus(on: node) }
            }
            .onChange(of: vm.tableSelection) {
                vm.syncSelectionFromTable()
            }
            .onKeyPress(.space) {
                vm.quickLook(vm.selection)
                return .handled
            }
        }
    }

    private func node(for id: FileNode.ID?, in rows: [FileNode]) -> FileNode? {
        rows.first { $0.id == id }
    }

    /// Path of the node's folder, relative to the scan root.
    private func location(of node: FileNode) -> String {
        guard let root = vm.root else { return node.url.deletingLastPathComponent().path }
        let full = node.url.deletingLastPathComponent().path
        let rootPath = root.url.path
        if full == rootPath { return root.name }
        if full.hasPrefix(rootPath + "/") {
            return root.name + "/" + full.dropFirst(rootPath.count + 1)
        }
        return full
    }
}
