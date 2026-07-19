import SwiftUI

enum Format {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: value)
    }

    static func percent(_ fraction: Double) -> String {
        fraction < 0.001 ? "<0.1%" : String(format: "%.1f%%", fraction * 100)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static func date(_ epochSeconds: Int64) -> String {
        guard epochSeconds > 0 else { return "—" }
        return dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }
}

enum Palette {
    /// Stable, well-separated hue for the i-th top-level slice (golden-ratio spacing).
    static func color(topIndex: Int, depth: Int, hovered: Bool = false) -> Color {
        let hue = (0.08 + Double(topIndex) * 0.6180339887).truncatingRemainder(dividingBy: 1)
        let saturation = max(0.28, 0.72 - Double(depth) * 0.11)
        let brightness = min(1.0, (hovered ? 0.98 : 0.82) + Double(depth) * 0.045)
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    static func otherColor(depth: Int, hovered: Bool = false) -> Color {
        Color(white: (hovered ? 0.75 : 0.6) + Double(depth) * 0.05)
    }
}
