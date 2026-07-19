import SwiftUI

/// Dropdown content for the menu-bar extra.
struct MenuBarView: View {
    let watcher: FreeSpaceWatcher
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(watcher.volumes) { volume in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(volume.name).font(.callout.bold())
                        Spacer()
                        Text("\(Format.bytes(volume.free)) free")
                            .font(.caption)
                            .foregroundStyle(volume.usedFraction > 0.95 ? .red : .secondary)
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
                    .frame(height: 6)
                }
            }

            if watcher.sortedSamples.count > 1 {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Startup disk free — last \(watcher.sortedSamples.count) days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Sparkline(values: watcher.sortedSamples.map { Double($0.free) })
                        .frame(height: 28)
                }
            }

            Divider()

            HStack {
                Button("Open DiskVis") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                SettingsLink {
                    Text("Settings…")
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 280)
        .onAppear { watcher.refresh() }
    }
}

struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1,
                  let minValue = values.min(), let maxValue = values.max() else { return }
            let range = max(maxValue - minValue, maxValue * 0.05, 1)
            let stepX = size.width / CGFloat(values.count - 1)
            var path = Path()
            for (index, value) in values.enumerated() {
                let x = CGFloat(index) * stepX
                let y = size.height - CGFloat((value - minValue) / range) * (size.height - 4) - 2
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
            if let last = values.last {
                let y = size.height - CGFloat((last - minValue) / range) * (size.height - 4) - 2
                let dot = CGRect(x: size.width - 2.5, y: y - 2.5, width: 5, height: 5)
                context.fill(Path(ellipseIn: dot), with: .color(.accentColor))
            }
        }
    }
}
