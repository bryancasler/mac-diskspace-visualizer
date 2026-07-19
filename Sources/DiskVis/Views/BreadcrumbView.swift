import SwiftUI

struct BreadcrumbView: View {
    @Environment(ScanViewModel.self) private var vm

    var body: some View {
        // FileNode is a plain class, not @Observable — reading .size below
        // needs an explicit dependency on tick to catch in-place mutations
        // from deletions elsewhere in the tree (matches currentChildren,
        // SunburstView, TreemapView).
        let _ = vm.tick
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(vm.path.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        vm.navigate(to: node)
                    } label: {
                        Text(node.name)
                            .font(.callout)
                            .fontWeight(index == vm.path.count - 1 ? .semibold : .regular)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == vm.path.count - 1 ? .primary : .secondary)
                }
                if let current = vm.current {
                    Text("— \(Format.bytes(current.size))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}
