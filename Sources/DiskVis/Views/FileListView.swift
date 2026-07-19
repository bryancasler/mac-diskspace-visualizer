import AppKit
import SwiftUI

/// Contents of the current folder.
///
/// Deliberately a custom List, not a SwiftUI `Table`: the AppKit-backed
/// Table commits its column widths against whatever width HSplitView's
/// early layout passes propose, and NSTableView never re-tiles committed
/// columns downward when the divider settles narrower — the trailing
/// column ends up permanently behind a horizontal scrollbar. Legacy
/// always-visible scrollbars (macOS default when a mouse is attached)
/// make it worse by stealing ~16pt of viewport and keeping the scrollbar
/// on screen. List rows lay out at the pane's actual width on every
/// pass — the flexible Name field absorbs all slack, so horizontal
/// overflow is impossible by construction and the pane can stay freely
/// resizable.
struct FileListView: View {
    @Environment(ScanViewModel.self) private var vm
    @State private var sortField: SortField = .size
    @State private var ascending = false

    enum SortField {
        case name, size, modified
    }

    // Fixed trailing-field widths, shared by the header and every row so
    // they always line up. Name takes whatever is left.
    static let sizeWidth: CGFloat = 78
    static let shareWidth: CGFloat = 130
    static let modifiedWidth: CGFloat = 90
    static let fieldSpacing: CGFloat = 10

    private var rows: [FileNode] {
        let children = vm.currentChildren
        let sorted: [FileNode]
        switch sortField {
        case .name:
            sorted = children.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            sorted = children.sorted { $0.size < $1.size }
        case .modified:
            sorted = children.sorted { $0.modified < $1.modified }
        }
        return ascending ? sorted : sorted.reversed()
    }

    var body: some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
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
    }

    private var header: some View {
        HStack(spacing: Self.fieldSpacing) {
            sortButton("Name", .name)
                .frame(maxWidth: .infinity, alignment: .leading)
            sortButton("Size", .size)
                .frame(width: Self.sizeWidth, alignment: .trailing)
            Text("Share")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: Self.shareWidth, alignment: .leading)
            sortButton("Modified", .modified)
                .frame(width: Self.modifiedWidth, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }

    private func sortButton(_ title: String, _ field: SortField) -> some View {
        Button {
            if sortField == field {
                ascending.toggle()
            } else {
                sortField = field
                // Fresh sort starts with the most useful direction:
                // names ascending, sizes/dates descending.
                ascending = field == .name
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if sortField == field {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
        .help("Sort by \(title.lowercased())")
    }

    private func row(_ node: FileNode) -> some View {
        HStack(spacing: Self.fieldSpacing) {
            NodeIcon(node: node)
            // The name is the single flexible field — it absorbs all slack
            // (no Spacer: an HStack Spacer outcompetes Text during
            // compression and crushes the name to "…").
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(node.isSynthetic ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.bytes(node.size))
                .monospacedDigit()
                .frame(width: Self.sizeWidth, alignment: .trailing)
            ShareBar(fraction: shareFraction(of: node))
                .frame(width: Self.shareWidth)
            Text(Format.date(node.modified))
                .foregroundStyle(.secondary)
                .frame(width: Self.modifiedWidth, alignment: .trailing)
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
