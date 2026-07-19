import AppKit
import SwiftUI

/// Flat file table: largest files (with age filter) or search results.
/// A custom List rather than a SwiftUI Table for the same reason as
/// FileListView (see the comment there): List rows fit the pane's real
/// width every pass, so nothing can fall off the right edge.
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

            header
            Divider()

            List(selection: $vm.tableSelection) {
                ForEach(rows) { node in
                    row(node)
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds(.enabled)
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

    private var header: some View {
        HStack(spacing: FileListView.fieldSpacing) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Size")
                .frame(width: FileListView.sizeWidth, alignment: .trailing)
            Text("Modified")
                .frame(width: FileListView.modifiedWidth, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }

    private func row(_ node: FileNode) -> some View {
        HStack(spacing: FileListView.fieldSpacing) {
            NodeIcon(node: node)
            // Flexible name block absorbs all slack (no Spacer — see
            // FileListView.row for why).
            VStack(alignment: .leading, spacing: 0) {
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(location(of: node))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.bytes(node.size))
                .monospacedDigit()
                .frame(width: FileListView.sizeWidth, alignment: .trailing)
            Text(Format.date(node.modified))
                .foregroundStyle(.secondary)
                .frame(width: FileListView.modifiedWidth, alignment: .trailing)
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
