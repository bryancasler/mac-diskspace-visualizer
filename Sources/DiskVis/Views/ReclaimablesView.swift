import SwiftUI

/// Sheet listing known reclaimable space: dev caches, app data, node_modules
/// from the current scan, and macOS-managed snapshots.
struct ReclaimablesView: View {
    @Environment(ScanViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingTrash: ReclaimableResult?
    @State private var confirmingSnapshot: TMSnapshot?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Reclaimable Space", systemImage: "sparkles")
                    .font(.title3.bold())
                Spacer()
                if vm.reclaimablesLoading {
                    ProgressView().controlSize(.small)
                }
                Button("Refresh") { refresh() }
                    .disabled(vm.reclaimablesLoading)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()

            List {
                if !vm.nodeModulesDirs.isEmpty {
                    Section("From this scan") {
                        nodeModulesRow
                    }
                }

                Section("Known caches & data") {
                    if vm.reclaimables.isEmpty && !vm.reclaimablesLoading {
                        Text("Nothing found — refresh to measure.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(vm.reclaimables) { result in
                        categoryRow(result)
                    }
                }

                Section("macOS-managed space") {
                    snapshotSection
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 720, height: 520)
        .onAppear { refresh() }
        .confirmationDialog(
            "Move “\(confirmingTrash?.category.title ?? "")” to the Trash?",
            isPresented: Binding(get: { confirmingTrash != nil }, set: { if !$0 { confirmingTrash = nil } }),
            titleVisibility: .visible
        ) {
            Button("Move to Trash (frees \(Format.bytes(confirmingTrash?.totalSize ?? 0)))", role: .destructive) {
                if let result = confirmingTrash {
                    vm.trash(result.nodes)
                    refresh()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmingTrash?.category.safety == .caution
                 ? "Read the description first — this one isn't just a cache. Restorable from the Trash until you empty it."
                 : "Restorable from the Trash until you empty it.")
        }
        .confirmationDialog(
            "Delete snapshot \(confirmingSnapshot?.deletableDate ?? "")?",
            isPresented: Binding(get: { confirmingSnapshot != nil }, set: { if !$0 { confirmingSnapshot = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Snapshot", role: .destructive) {
                if let snapshot = confirmingSnapshot { vm.deleteSnapshot(snapshot) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes this Time Machine restore point. Space is reclaimed immediately.")
        }
    }

    private func refresh() {
        vm.loadReclaimables()
    }

    private var nodeModulesRow: some View {
        let dirs = vm.nodeModulesDirs
        let total = dirs.reduce(Int64(0)) { $0 + $1.size }
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("node_modules folders").bold()
                    SafetyBadge(safety: .safe)
                }
                Text("\(dirs.count) folders in the scanned tree. Reinstall with npm/pnpm/yarn per project when needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.bytes(total)).monospacedDigit().bold()
            Button("Collect All") {
                for dir in dirs { vm.addToCollector(dir) }
            }
            .help("Add every node_modules folder to the Collector")
        }
        .padding(.vertical, 2)
    }

    private func categoryRow(_ result: ReclaimableResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.category.safety == .safe ? "checkmark.seal" : "exclamationmark.triangle")
                .foregroundStyle(result.category.safety == .safe ? Color.green : .orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(result.category.title).bold()
                    SafetyBadge(safety: result.category.safety)
                }
                Text(result.category.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(Format.bytes(result.totalSize)).monospacedDigit().bold()
            HStack(spacing: 6) {
                Button {
                    if let node = result.nodes.first { vm.reveal(node) }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Reveal in Finder")
                if result.category.id != "trash" {
                    Button {
                        for node in result.nodes { vm.addToCollector(node) }
                    } label: {
                        Image(systemName: "basket")
                    }
                    .help("Add to Collector")
                    Button(role: .destructive) {
                        confirmingTrash = result
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Move to Trash…")
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var snapshotSection: some View {
        if let volumeUsed = vm.volumeUsedBytes, let root = vm.root, volumeUsed > root.size {
            Text("Files account for \(Format.bytes(root.size)) of \(Format.bytes(volumeUsed)) used on this volume. The rest lives in the snapshots below, purgeable caches, and folders the app can't read.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if vm.snapshots.isEmpty {
            Text("No local snapshots.")
                .foregroundStyle(.secondary)
        }
        ForEach(vm.snapshots) { snapshot in
            HStack {
                Image(systemName: snapshot.isOSUpdate ? "gearshape.arrow.triangle.2.circlepath" : "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.deletableDate ?? snapshot.name)
                    if snapshot.isOSUpdate {
                        Text("Staged macOS update — its space frees itself once the update installs. Not deletable here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if snapshot.deletableDate != nil {
                    Button("Delete…", role: .destructive) {
                        confirmingSnapshot = snapshot
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        if let message = vm.snapshotMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

struct SafetyBadge: View {
    let safety: ReclaimableCategory.Safety

    var body: some View {
        Text(safety == .safe ? "SAFE" : "CAUTION")
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                (safety == .safe ? Color.green : Color.orange).opacity(0.18),
                in: Capsule()
            )
            .foregroundStyle(safety == .safe ? Color.green : Color.orange)
    }
}
