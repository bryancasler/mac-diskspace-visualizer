import SwiftUI

struct DetailBar: View {
    @Environment(ScanViewModel.self) private var vm
    @State private var confirmingTrash = false

    var body: some View {
        HStack(spacing: 12) {
            if let node = vm.selection {
                NodeIcon(node: node)
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.name).font(.callout).bold().lineLimit(1)
                    Text(node.isSynthetic ? "Aggregated small items" : node.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(Format.bytes(node.size))
                    .font(.callout)
                    .monospacedDigit()

                if !node.isSynthetic {
                    Button("Quick Look") { vm.quickLook(node) }
                    Button("Reveal in Finder") { vm.reveal(node) }
                    Button("Collect") { vm.addToCollector(node) }
                        .keyboardShortcut("k", modifiers: .command)
                        .disabled(vm.isInCollector(node))
                        .help("Add to the Collector basket (⌘K)")
                    Button("Move to Trash", role: .destructive) { confirmingTrash = true }
                        .keyboardShortcut(.delete, modifiers: .command)
                }
            } else {
                Text("Select an item to see actions")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if let volumeUsed = vm.volumeUsedBytes,
               let root = vm.root,
               volumeUsed - root.size > 2_000_000_000 {
                Label(
                    "Files: \(Format.bytes(root.size)) of \(Format.bytes(volumeUsed)) used — the rest is macOS-managed (snapshots, purgeable space) or unreadable folders",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Local Time Machine snapshots, staged OS updates, and purgeable caches occupy space but aren't visible as files. macOS frees purgeable space automatically when needed.")
            }

            if vm.inaccessibleCount > 0 {
                Label(
                    "\(vm.inaccessibleCount) folders couldn't be read — grant Full Disk Access for a complete picture",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .help("System Settings → Privacy & Security → Full Disk Access")
            }

            if vm.reclaimedBytes > 0 {
                Label("Reclaimed: \(Format.bytes(vm.reclaimedBytes))", systemImage: "arrow.down.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .confirmationDialog(
            "Move \"\(vm.selection?.name ?? "")\" to the Trash?",
            isPresented: $confirmingTrash,
            titleVisibility: .visible
        ) {
            Button("Move to Trash (frees \(Format.bytes(vm.selection?.size ?? 0)))", role: .destructive) {
                if let node = vm.selection { vm.moveToTrash(node) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can restore it from the Trash until you empty it.")
        }
    }
}
