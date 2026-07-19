import SwiftUI

/// Trailing inspector: staging basket for items to delete in one action.
struct CollectorView: View {
    @Environment(ScanViewModel.self) private var vm
    @State private var confirmingEmpty = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Collector", systemImage: "basket")
                    .font(.headline)
                Spacer()
                if !vm.collector.isEmpty {
                    Button("Clear") { vm.collector.removeAll() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)

            Divider()

            if vm.collector.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "basket")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Collect items while you explore,\nthen delete them all at once.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Right-click anything → “Add to Collector” (⌘K)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(vm.collector) { node in
                        HStack(spacing: 6) {
                            NodeIcon(node: node)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(node.name).lineLimit(1)
                                Text(node.url.deletingLastPathComponent().path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(Format.bytes(node.size))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button {
                                vm.removeFromCollector(node)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove from Collector")
                        }
                    }
                }
                .listStyle(.inset)

                Divider()

                VStack(spacing: 8) {
                    HStack {
                        Text("\(vm.collector.count) items")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Format.bytes(vm.collectorTotal))
                            .bold()
                            .monospacedDigit()
                    }
                    .font(.callout)
                    Button(role: .destructive) {
                        confirmingEmpty = true
                    } label: {
                        Label("Move All to Trash…", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
                .padding(10)
            }
        }
        .confirmationDialog(
            "Move \(vm.collector.count) items to the Trash?",
            isPresented: $confirmingEmpty,
            titleVisibility: .visible
        ) {
            Button("Move to Trash (frees \(Format.bytes(vm.collectorTotal)))", role: .destructive) {
                vm.emptyCollector()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything can be restored from the Trash until you empty it.")
        }
    }
}
