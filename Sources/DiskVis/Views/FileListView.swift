import AppKit
import SwiftUI

struct FileListView: View {
    @Environment(ScanViewModel.self) private var vm
    @State private var sortOrder = [KeyPathComparator(\FileNode.size, order: .reverse)]

    var body: some View {
        @Bindable var vm = vm
        let rows = vm.currentChildren.sorted(using: sortOrder)

        Table(rows, selection: $vm.tableSelection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { node in
                HStack(spacing: 6) {
                    NodeIcon(node: node)
                    Text(node.name)
                        .lineLimit(1)
                        .foregroundStyle(node.isSynthetic ? .secondary : .primary)
                }
            }
            .width(min: 160, ideal: 260)

            TableColumn("Size", value: \.size) { node in
                Text(Format.bytes(node.size))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90, max: 120)

            TableColumn("Share", value: \.size) { node in
                ShareBar(fraction: shareFraction(of: node))
            }
            .width(min: 90, ideal: 140)

            TableColumn("Modified", value: \.modified) { node in
                Text(Format.date(node.modified))
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100, max: 140)
        }
        .contextMenu(forSelectionType: FileNode.ID.self) { ids in
            if let node = node(for: ids.first) {
                if node.isDirectory && !node.isSynthetic {
                    Button("Open") { vm.drill(into: node) }
                }
                if !node.isSynthetic {
                    Button("Quick Look") { vm.quickLook(node) }
                    Button("Reveal in Finder") { vm.reveal(node) }
                    Divider()
                    Button("Add to Collector") { vm.addToCollector(node) }
                        .disabled(vm.isInCollector(node))
                    Button("Move to Trash", role: .destructive) { vm.requestTrash([node]) }
                }
            }
        } primaryAction: { ids in
            guard let node = node(for: ids.first) else { return }
            if node.isDirectory && !node.isSynthetic {
                vm.drill(into: node)
            }
        }
        .onChange(of: vm.tableSelection) {
            vm.syncSelectionFromTable()
        }
        .onKeyPress(.space) {
            vm.quickLook(vm.selection)
            return .handled
        }
    }

    private func node(for id: FileNode.ID?) -> FileNode? {
        vm.currentChildren.first { $0.id == id }
    }

    private func shareFraction(of node: FileNode) -> Double {
        guard let parent = vm.current, parent.size > 0 else { return 0 }
        return Double(node.size) / Double(parent.size)
    }
}

struct NodeIcon: View {
    let node: FileNode

    var body: some View {
        if node.isSynthetic {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        } else if node.isInaccessible {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
                .frame(width: 16, height: 16)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
                .resizable()
                .frame(width: 16, height: 16)
        }
    }
}

struct ShareBar: View {
    let fraction: Double

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(.tint)
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
            Text(Format.percent(fraction))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
        }
    }
}
