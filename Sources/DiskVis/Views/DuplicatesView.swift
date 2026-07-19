import SwiftUI

/// Right-pane mode: duplicate file groups with keep-newest workflow.
struct DuplicatesView: View {
    @Environment(ScanViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let groups = vm.duplicateGroups {
                    Text("\(groups.count) groups — \(Format.bytes(groups.reduce(0) { $0 + $1.wastedBytes })) wasted")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Find files with identical content in this scan.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if vm.dupesLoading {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { vm.cancelDuplicates() }
                } else {
                    Button(vm.duplicateGroups == nil ? "Find Duplicates" : "Find Again") {
                        vm.findDuplicates()
                    }
                    .disabled(vm.root == nil)
                }
            }
            .padding(10)

            Divider()

            if let groups = vm.duplicateGroups, !groups.isEmpty {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                                HStack(spacing: 6) {
                                    NodeIcon(node: file)
                                    VStack(alignment: .leading, spacing: 0) {
                                        HStack(spacing: 6) {
                                            Text(file.name).lineLimit(1)
                                            if index == 0 {
                                                Text("NEWEST")
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 4)
                                                    .background(Color.green.opacity(0.18), in: Capsule())
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                        Text(file.url.deletingLastPathComponent().path)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                    Text(Format.date(file.modified))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .contextMenu {
                                    Button("Reveal in Finder") { vm.reveal(file) }
                                    Button("Quick Look") { vm.quickLook(file) }
                                    Button("Add to Collector") { vm.addToCollector(file) }
                                        .disabled(vm.isInCollector(file))
                                }
                            }
                        } header: {
                            HStack {
                                Text("\(group.files.count) × \(Format.bytes(group.size)) — wastes \(Format.bytes(group.wastedBytes))")
                                Spacer()
                                Button("Keep Newest, Collect Rest") {
                                    for file in group.files.dropFirst() {
                                        vm.addToCollector(file)
                                    }
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                .listStyle(.inset)

                Divider()
                Text("Hard links are excluded. APFS clone files can't be detected, so deleting a duplicate may free less than shown.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(6)
            } else if vm.duplicateGroups != nil {
                ContentUnavailableView(
                    "No duplicates found",
                    systemImage: "checkmark.circle",
                    description: Text("No identical files over \(Format.bytes(DuplicateFinder.minSize)) in this scan.")
                )
            } else if vm.dupesLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Hashing candidates…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Duplicates",
                    systemImage: "doc.on.doc",
                    description: Text("Groups files by size, then compares content hashes. Only files over \(Format.bytes(DuplicateFinder.minSize)) are considered.")
                )
            }
        }
    }
}
