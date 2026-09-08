import AppKit

/// Draws the little level meter that lives in the menu bar.
enum LevelBarImage {

    static let size = NSSize(width: 30, height: 16)

    static func make(fill: Double, thresholdMark: Double, color: NSColor) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            let barHeight: CGFloat = 6
            let track = NSRect(
                x: 0,
                y: (size.height - barHeight) / 2,
                width: size.width,
                height: barHeight
            )
            let radius = barHeight / 2

            NSColor.labelColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

            let clamped = min(max(fill, 0), 1)
            if clamped > 0 {
                // Always leave at least a dot visible so the meter reads as live.
                let width = max(track.width * CGFloat(clamped), barHeight)
                var filled = track
                filled.size.width = width
                color.setFill()
                NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
            }

            // Tick showing where "shouting" starts.
            let markX = track.minX + track.width * CGFloat(min(max(thresholdMark, 0), 1))
            let mark = NSRect(x: markX - 0.75, y: track.minY - 2.5, width: 1.5, height: barHeight + 5)
            NSColor.labelColor.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: mark, xRadius: 0.75, yRadius: 0.75).fill()

            return true
        }
        image.isTemplate = false
        return image
    }
}
