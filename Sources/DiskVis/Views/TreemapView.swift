import SwiftUI

struct TreeRect {
    let node: FileNode?
    let label: String
    let sizeBytes: Int64
    let rect: CGRect
    let depth: Int
    let topIndex: Int
}

/// Squarified treemap of the current node: children as blocks, grandchildren
/// nested inside. Same interaction semantics as the sunburst.
struct TreemapView: View {
    let center: FileNode
    let tick: Int
    let selection: FileNode?
    var onSelect: (FileNode) -> Void
    var onDrill: (FileNode) -> Void
    var onUp: () -> Void
    var onCollect: ((FileNode) -> Void)?
    var onTrash: ((FileNode) -> Void)?
    var onReveal: ((FileNode) -> Void)?

    @State private var hoverPoint: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let rects = buildRects(in: geo.size)
            let hovered = hoverPoint.flatMap { hit(at: $0, rects: rects) }

            ZStack {
                Canvas { context, _ in
                    draw(rects: rects, hovered: hovered, in: &context)
                }
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
                    guard let hit = hit(at: value.location, rects: rects), let node = hit.node else { return }
                    if node.isDirectory && !node.isSynthetic {
                        onDrill(node)
                    } else {
                        onSelect(node)
                    }
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
        .accessibilityLabel("Disk usage treemap for \(center.name)")
    }

    // MARK: - Layout

    private func buildRects(in size: CGSize) -> [TreeRect] {
        _ = tick
        var rects: [TreeRect] = []
        let outer = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
        guard center.size > 0, outer.width > 20, outer.height > 20 else { return rects }

        let children = center.children.filter { $0.size > 0 }
        let level0 = squarify(sizes: children.map { Double($0.size) }, in: outer)
        for (index, child) in children.enumerated() {
            let rect = level0[index].insetBy(dx: 1.5, dy: 1.5)
            guard rect.width > 2, rect.height > 2 else { continue }
            rects.append(TreeRect(
                node: child, label: child.name, sizeBytes: child.size,
                rect: rect, depth: 0, topIndex: index
            ))
            // Nest grandchildren when there's room, leaving a title strip.
            if child.isDirectory, rect.width > 70, rect.height > 52 {
                let inner = CGRect(
                    x: rect.minX + 4, y: rect.minY + 20,
                    width: rect.width - 8, height: rect.height - 24
                )
                let grandchildren = child.children.filter { $0.size > 0 }
                let level1 = squarify(sizes: grandchildren.map { Double($0.size) }, in: inner)
                for (gi, grandchild) in grandchildren.enumerated() {
                    let grect = level1[gi].insetBy(dx: 1, dy: 1)
                    guard grect.width > 3, grect.height > 3 else { continue }
                    rects.append(TreeRect(
                        node: grandchild, label: grandchild.name, sizeBytes: grandchild.size,
                        rect: grect, depth: 1, topIndex: index
                    ))
                }
            }
        }
        return rects
    }

    /// Squarified treemap layout (Bruls, Huizing, van Wijk). `sizes` must be
    /// sorted descending (scan children already are). Returns one rect per size.
    private func squarify(sizes: [Double], in rect: CGRect) -> [CGRect] {
        var results: [CGRect] = Array(repeating: .zero, count: sizes.count)
        let total = sizes.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return results }
        let scale = Double(rect.width * rect.height) / total

        var remaining = rect
        var index = 0

        while index < sizes.count {
            // Grow the row while the worst aspect ratio improves.
            let shortSide = Double(min(remaining.width, remaining.height))
            guard shortSide > 0 else { break }
            var rowEnd = index
            var rowArea = 0.0
            var bestWorst = Double.infinity
            while rowEnd < sizes.count {
                let area = sizes[rowEnd] * scale
                let newRowArea = rowArea + area
                let rowThickness = newRowArea / shortSide
                var worst = 1.0
                for i in index...rowEnd {
                    let itemLength = (sizes[i] * scale) / rowThickness
                    worst = max(worst, max(itemLength / rowThickness, rowThickness / itemLength))
                }
                if worst > bestWorst { break }
                bestWorst = worst
                rowArea = newRowArea
                rowEnd += 1
            }
            if rowEnd == index { rowEnd = index + 1; rowArea = sizes[index] * scale }

            // Lay the row along the short side of the remaining rect.
            let thickness = CGFloat(rowArea / shortSide)
            var offset: CGFloat = 0
            let horizontal = remaining.width >= remaining.height
            for i in index..<rowEnd {
                let length = CGFloat((sizes[i] * scale) / Double(thickness))
                results[i] = horizontal
                    ? CGRect(x: remaining.minX, y: remaining.minY + offset, width: thickness, height: length)
                    : CGRect(x: remaining.minX + offset, y: remaining.minY, width: length, height: thickness)
                offset += length
            }
            remaining = horizontal
                ? CGRect(x: remaining.minX + thickness, y: remaining.minY,
                         width: remaining.width - thickness, height: remaining.height)
                : CGRect(x: remaining.minX, y: remaining.minY + thickness,
                         width: remaining.width, height: remaining.height - thickness)
            index = rowEnd
        }
        return results
    }

    // MARK: - Drawing

    private func draw(rects: [TreeRect], hovered: TreeRect?, in context: inout GraphicsContext) {
        for item in rects {
            let isHovered = hovered.map { $0.rect == item.rect } ?? false
            let isSelected = selection != nil && item.node === selection
            let color: Color = item.node?.isSynthetic == true
                ? Palette.otherColor(depth: item.depth, hovered: isHovered)
                : Palette.color(topIndex: item.topIndex, depth: item.depth, hovered: isHovered || isSelected)

            let path = Path(roundedRect: item.rect, cornerRadius: 3)
            context.fill(path, with: .color(item.depth == 0 ? color.opacity(0.55) : color))
            if isSelected {
                context.stroke(path, with: .color(.primary), lineWidth: 1.5)
            }

            // Label when there's room
            if item.rect.width > 64, item.rect.height > 16 {
                let title = Text("\(item.label)  \(Format.bytes(item.sizeBytes))")
                    .font(.caption2.weight(item.depth == 0 ? .semibold : .regular))
                    .foregroundStyle(item.depth == 0 ? Color.primary : Color.black.opacity(0.65))
                context.drawLayer { layer in
                    layer.clip(to: Path(item.rect.insetBy(dx: 3, dy: 1)))
                    layer.draw(
                        title,
                        at: CGPoint(x: item.rect.minX + 5, y: item.rect.minY + 3),
                        anchor: .topLeading
                    )
                }
            }
        }
    }

    private func hit(at point: CGPoint, rects: [TreeRect]) -> TreeRect? {
        // Deepest block wins
        rects.last { $0.rect.contains(point) }
    }

    private func tooltip(for item: TreeRect, at point: CGPoint, in size: CGSize) -> some View {
        let fraction = center.size > 0 ? Double(item.sizeBytes) / Double(center.size) : 0
        return VStack(alignment: .leading, spacing: 2) {
            Text(item.label).font(.callout).bold().lineLimit(1)
            Text("\(Format.bytes(item.sizeBytes)) — \(Format.percent(fraction)) of \(center.name)")
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
}
