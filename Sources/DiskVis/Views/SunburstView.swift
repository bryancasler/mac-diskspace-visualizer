import SwiftUI

struct SunArc {
    let node: FileNode?          // nil for aggregated "Other" arcs
    let label: String
    let sizeBytes: Int64
    let startDeg: Double
    let endDeg: Double
    let depth: Int
    let topIndex: Int
}

struct SunburstView: View {
    let center: FileNode
    let tick: Int
    let selection: FileNode?
    var onSelect: (FileNode) -> Void
    var onDrill: (FileNode) -> Void
    var onUp: () -> Void
    /// Optional context-menu actions for a right-clicked node.
    var onCollect: ((FileNode) -> Void)?
    var onTrash: ((FileNode) -> Void)?
    var onReveal: ((FileNode) -> Void)?

    @State private var hoverPoint: CGPoint?

    private static let maxDepth = 4
    private static let minSweepDeg = 0.6
    private static let holeFraction = 0.42  // hole radius as fraction of max radius

    var body: some View {
        GeometryReader { geo in
            let arcs = buildArcs()
            let hovered = hoverPoint.flatMap { arc(at: $0, in: geo.size, arcs: arcs) }

            ZStack {
                Canvas { context, size in
                    draw(arcs: arcs, hovered: hovered, in: &context, size: size)
                }
                centerLabel(in: geo.size)
                if let hovered, let point = hoverPoint {
                    tooltip(for: hovered, at: point, in: geo.size)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hoverPoint = point
                case .ended: hoverPoint = nil
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { value in
                    handleTap(at: value.location, in: geo.size, arcs: arcs)
                }
            )
            .contextMenu {
                if let node = hovered?.node, !node.isSynthetic {
                    Text("\(node.name) — \(Format.bytes(node.size))")
                    if let onReveal {
                        Button("Reveal in Finder") { onReveal(node) }
                    }
                    if let onCollect {
                        Button("Add to Collector") { onCollect(node) }
                    }
                    if let onTrash {
                        Button("Move to Trash", role: .destructive) { onTrash(node) }
                    }
                }
            }
        }
        .accessibilityLabel("Disk usage sunburst chart for \(center.name)")
    }

    // MARK: - Geometry

    private func layout(in size: CGSize) -> (center: CGPoint, hole: CGFloat, ringWidth: CGFloat) {
        let maxRadius = min(size.width, size.height) / 2 - 12
        let hole = maxRadius * Self.holeFraction
        let ringWidth = (maxRadius - hole) / CGFloat(Self.maxDepth)
        return (CGPoint(x: size.width / 2, y: size.height / 2), hole, ringWidth)
    }

    // MARK: - Arc model

    private func buildArcs() -> [SunArc] {
        _ = tick
        var arcs: [SunArc] = []
        appendArcs(of: center, start: -90, sweep: 360, depth: 0, topIndex: 0, into: &arcs)
        return arcs
    }

    private func appendArcs(
        of node: FileNode, start: Double, sweep: Double,
        depth: Int, topIndex: Int, into arcs: inout [SunArc]
    ) {
        guard depth < Self.maxDepth, node.size > 0 else { return }
        var angle = start
        var otherSize: Int64 = 0
        var otherCount = 0

        for (index, child) in node.children.enumerated() {
            let childSweep = Double(child.size) / Double(node.size) * sweep
            let childTopIndex = depth == 0 ? index : topIndex
            // Children are sorted by size, so everything after the first
            // too-small slice is also too small — aggregate the tail.
            if childSweep < Self.minSweepDeg {
                otherSize += child.size
                otherCount += 1
                continue
            }
            arcs.append(SunArc(
                node: child, label: child.name, sizeBytes: child.size,
                startDeg: angle, endDeg: angle + childSweep,
                depth: depth, topIndex: childTopIndex
            ))
            if child.isDirectory {
                appendArcs(of: child, start: angle, sweep: childSweep,
                           depth: depth + 1, topIndex: childTopIndex, into: &arcs)
            }
            angle += childSweep
        }

        if otherCount > 0, start + sweep - angle > 0.05 {
            arcs.append(SunArc(
                node: nil, label: "\(otherCount) smaller items", sizeBytes: otherSize,
                startDeg: angle, endDeg: start + sweep,
                depth: depth, topIndex: topIndex
            ))
        }
    }

    // MARK: - Drawing

    private func draw(arcs: [SunArc], hovered: SunArc?, in context: inout GraphicsContext, size: CGSize) {
        let layout = layout(in: size)
        guard layout.ringWidth > 2 else { return }

        for arc in arcs {
            let inner = layout.hole + CGFloat(arc.depth) * layout.ringWidth
            let outer = inner + layout.ringWidth - 1
            var path = Path()
            path.addArc(
                center: layout.center, radius: outer,
                startAngle: .degrees(arc.startDeg), endAngle: .degrees(arc.endDeg),
                clockwise: false
            )
            path.addArc(
                center: layout.center, radius: inner,
                startAngle: .degrees(arc.endDeg), endAngle: .degrees(arc.startDeg),
                clockwise: true
            )
            path.closeSubpath()

            let isHovered = hovered.map { $0.startDeg == arc.startDeg && $0.depth == arc.depth } ?? false
            let isSelected = selection != nil && arc.node === selection
            let color: Color = arc.node == nil
                ? Palette.otherColor(depth: arc.depth, hovered: isHovered)
                : Palette.color(topIndex: arc.topIndex, depth: arc.depth, hovered: isHovered || isSelected)

            context.fill(path, with: .color(color))
            if arc.endDeg - arc.startDeg > 0.8 {
                context.stroke(path, with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 1)
            }
            if isSelected {
                context.stroke(path, with: .color(.primary), lineWidth: 1.5)
            }
        }

        // Center hole ring
        let holeRect = CGRect(
            x: layout.center.x - layout.hole, y: layout.center.y - layout.hole,
            width: layout.hole * 2, height: layout.hole * 2
        )
        context.stroke(Path(ellipseIn: holeRect), with: .color(.secondary.opacity(0.25)), lineWidth: 1)
    }

    private func centerLabel(in size: CGSize) -> some View {
        let layout = layout(in: size)
        return VStack(spacing: 4) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
            Text(center.name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(Format.bytes(center.size))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if center.parent != nil {
                Text("Click to go up")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: layout.hole * 1.5)
        .position(layout.center)
        .allowsHitTesting(false)
    }

    private func tooltip(for arc: SunArc, at point: CGPoint, in size: CGSize) -> some View {
        let fraction = center.size > 0 ? Double(arc.sizeBytes) / Double(center.size) : 0
        return VStack(alignment: .leading, spacing: 2) {
            Text(arc.label).font(.callout).bold().lineLimit(1)
            Text("\(Format.bytes(arc.sizeBytes)) — \(Format.percent(fraction)) of \(center.name)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 3)
        .position(
            x: min(max(point.x, 110), size.width - 110),
            y: max(point.y - 36, 28)
        )
        .allowsHitTesting(false)
    }

    // MARK: - Hit testing

    private func arc(at point: CGPoint, in size: CGSize, arcs: [SunArc]) -> SunArc? {
        let layout = layout(in: size)
        let dx = point.x - layout.center.x
        let dy = point.y - layout.center.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance >= layout.hole, layout.ringWidth > 0 else { return nil }

        let depth = Int((distance - layout.hole) / layout.ringWidth)
        guard depth < Self.maxDepth else { return nil }

        var degrees = atan2(dy, dx) * 180 / .pi   // (-180, 180], 0 at 3 o'clock
        if degrees < -90 { degrees += 360 }       // match arc range [-90, 270)

        return arcs.first { $0.depth == depth && degrees >= $0.startDeg && degrees < $0.endDeg }
    }

    private func handleTap(at point: CGPoint, in size: CGSize, arcs: [SunArc]) {
        let layout = layout(in: size)
        let dx = point.x - layout.center.x
        let dy = point.y - layout.center.y
        if sqrt(dx * dx + dy * dy) < layout.hole {
            onUp()
            return
        }
        guard let arc = arc(at: point, in: size, arcs: arcs), let node = arc.node else { return }
        if node.isDirectory && !node.isSynthetic {
            onDrill(node)
        } else {
            onSelect(node)
        }
    }
}
