import AppKit

@MainActor
final class GameButton: NSButton {
    var style: Style
    var isSelected = false {
        didSet { needsDisplay = true }
    }

    var tint: NSColor = Theme.gold {
        didSet { needsDisplay = true }
    }

    var actionHandler: (() -> Void)?

    init(_ title: String, style: Style = .red, actionHandler: (() -> Void)? = nil) {
        self.style = style
        self.actionHandler = actionHandler
        super.init(frame: .zero)

        self.title = title
        setUpStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        // Center the one-point outline half a point inside the button bounds.
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let isPressed = cell?.isHighlighted == true

        if style != .subtle {
            decorate(rect, isPressed: isPressed)
        }

        let text = (style == .checkbox ? (isSelected ? "✓" : "") : title) as NSString
        let drawingFont = fittedFont(for: text)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: drawingFont, .foregroundColor: isEnabled ? tint : Theme.mutedGold,
            .shadow: Theme.shadow()
        ]

        // Selected labels sit one point lower to suggest a depressed face.
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2 + (isSelected ? -1 : 0)
            ),
            withAttributes: attributes
        )
    }

    // MARK: - Text and decoration

    private func fittedFont(for text: NSString) -> NSFont {
        // Shrink in half-point steps to fit translated labels, stopping at the
        // minimum readable size. Checkbox glyphs keep their original font.
        let baseFont = font ?? Theme.decorative(12)
        var drawingFont = baseFont

        guard style != .checkbox else { return baseFont }

        let minimumSize = Theme.margin()
        let availableWidth = max(0, bounds.width - Theme.margin())
        var fittedSize = baseFont.pointSize
        while fittedSize > minimumSize
            && text.size(withAttributes: [.font: drawingFont]).width > availableWidth
        {
            fittedSize = max(minimumSize, fittedSize - 0.5)
            drawingFont = NSFont(descriptor: baseFont.fontDescriptor, size: fittedSize) ?? baseFont
        }

        return drawingFont
    }

    @objc private func activate() {
        actionHandler?()
    }

    private func decorate(_ rect: CGRect, isPressed: Bool) {
        // A downward gradient and two inset strokes form the raised button bevel.
        let face = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        NSGradient(colors: style.gradientColors(pressed: isPressed))?.draw(in: face, angle: 270)

        (isSelected ? Theme.gold : Theme.mutedGold)
            .setStroke()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            .stroke()
        NSColor.black.withAlphaComponent(0.85)
            .setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
            .stroke()
        NSColor.white.withAlphaComponent(0.13)
            .setStroke()

        let highlight = NSBezierPath()
        highlight.move(to: NSPoint(x: 3, y: bounds.height - 3))
        highlight.line(to: NSPoint(x: bounds.width - 3, y: bounds.height - 3))
        highlight.stroke()
    }

    // MARK: - Setup

    private func setUpStyle() {
        isBordered = false
        font = Theme.decorative(12, bold: true)
        translatesAutoresizingMaskIntoConstraints = false
        target = self
        self.action = #selector(activate)
        setAccessibilityLabel(title)
    }
}

// MARK: - Style

extension GameButton {
    enum Style: Equatable {
        case red, dark, checkbox, subtle

        func gradientColors(pressed: Bool) -> [NSColor] {
            switch self {
            case .red:
                pressed
                    ? [NSColor(hex: 0x420e0b), NSColor(hex: 0x74221a)]
                    : [NSColor(hex: 0x9d2c20), NSColor(hex: 0x4b0d09)]
            default:
                pressed
                    ? [NSColor(hex: 0x51492b), NSColor(hex: 0x242015)]
                    : [NSColor(hex: 0x30332d), NSColor(hex: 0x111311)]
            }
        }
    }
}
