import AppKit
import SwiftUI

struct WelcomeView: View {
    @Environment(ScanViewModel.self) private var vm
    @State private var volumes: [VolumeInfo] = []

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)

            VStack(spacing: 6) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("DiskVis")
                    .font(.largeTitle.bold())
                Text("See what's eating your disk — and free it up.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(volumes) { volume in
                    VolumeRow(volume: volume) {
                        vm.startScan(url: volume.url)
                    }
                }
            }
            .frame(maxWidth: 520)

            HStack(spacing: 10) {
                QuickScanButton(title: "Home", symbol: "house",
                                url: FileManager.default.homeDirectoryForCurrentUser)
                QuickScanButton(title: "Downloads", symbol: "arrow.down.circle",
                                url: FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads"))
                QuickScanButton(title: "Applications", symbol: "app.badge",
                                url: URL(fileURLWithPath: "/Applications"))
                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Folder…", systemImage: "folder")
                }
                .controlSize(.large)
            }

            if let error = vm.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Text("Tip: scanning your home folder is usually the fastest way to find reclaimable space. Scanning a whole disk may need Full Disk Access (System Settings → Privacy & Security).")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: loadVolumes)
    }

    private func loadVolumes() {
        volumes = VolumeInfo.mounted()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            vm.startScan(url: url)
        }
    }
}

private struct VolumeRow: View {
    let volume: VolumeInfo
    let onScan: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "internaldrive")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(volume.name).font(.headline)
                    Spacer()
                    Text("\(Format.bytes(volume.free)) free of \(Format.bytes(volume.total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(volume.usedFraction > 0.9 ? Color.red : Color.accentColor)
                            .frame(width: max(3, geo.size.width * volume.usedFraction))
                    }
                }
                .frame(height: 8)
            }
            Button("Scan", action: onScan)
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct QuickScanButton: View {
    @Environment(ScanViewModel.self) private var vm
    let title: String
    let symbol: String
    let url: URL

    var body: some View {
        Button {
            vm.startScan(url: url)
        } label: {
            Label(title, systemImage: symbol)
        }
        .controlSize(.large)
    }
}
