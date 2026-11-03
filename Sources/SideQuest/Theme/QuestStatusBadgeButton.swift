import AppKit

@MainActor
final class QuestStatusBadgeButton: NSButton {
    private let progress: QuestProgress
    private let isFocused: Bool
    private var actionHandler: (() -> Void)?

    init(progress: QuestProgress, isFocused: Bool, action: @escaping () -> Void) {
        self.progress = progress
        self.isFocused = isFocused
        actionHandler = action
        super.init(frame: .zero)
        title = progress.icon
        isBordered = false
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        target = self
        self.action = #selector(activate)
        let focusHint =
            isFocused
            ? L10n.text("focused_quest_click_to_unfocus")
            : L10n.text("focus_quest_tooltip")
        toolTip = L10n.text("quest_status_tooltip", progress.title, focusHint)
        let focusState = isFocused ? L10n.text("focused") : L10n.text("not_selected")
        setAccessibilityValue(L10n.text("quest_status_accessibility", progress.title, focusState))
        // The 30-point circle matches the tracker's heading indent.
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    @objc private func activate() {
        actionHandler?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        let pressed = cell?.isHighlighted == true
        let outerRect = bounds.insetBy(dx: 2, dy: 2)
        let outer = NSBezierPath(ovalIn: outerRect)

        drawRim(outer)
        drawFace(in: outerRect, pressed: pressed)
        drawGlyph(pressed: pressed)
    }

    // MARK: - Badge drawing

    private func drawRim(_ outer: NSBezierPath) {
        // Keep the glow scoped to the rim so it does not shadow the glyph or face.
        NSGraphicsContext.saveGraphicsState()
        let glow = Theme.shadow(
            isFocused ? NSColor(hex: 0xffd34e, alpha: 0.55) : .black, blur: isFocused ? 4 : 2)
        glow.set()
        let rimColors: [NSColor] =
            isFocused
            ? [NSColor(hex: 0xfff3aa), NSColor(hex: 0xb27c22), NSColor(hex: 0xf3d178)]
            : [NSColor(hex: 0xb38b50), NSColor(hex: 0x4b2c16), NSColor(hex: 0x9c7037)]
        NSGradient(colors: rimColors)!.draw(in: outer, angle: 270)
        NSGraphicsContext.restoreGraphicsState()
        NSColor(hex: 0x1b1008).setStroke()
        outer.lineWidth = 0.8
        outer.stroke()
    }

    private func drawFace(in outerRect: NSRect, pressed: Bool) {
        // A three-point inset leaves the metal rim visible around the face.
        let inner = NSBezierPath(ovalIn: outerRect.insetBy(dx: 3, dy: 3))
        let fillColors: [NSColor] =
            isFocused
            ? [NSColor(hex: 0xffeb7c), NSColor(hex: pressed ? 0xc89320 : 0xe9b62c), NSColor(hex: 0xbf8118)]
            : [NSColor(hex: pressed ? 0x68441f : 0x4b3018), NSColor(hex: 0x20150d)]
        NSGradient(colors: fillColors)!.draw(in: inner, angle: 270)
        (isFocused ? NSColor(hex: 0xffe78a) : NSColor(hex: 0x8f622e)).setStroke()
        inner.lineWidth = 0.7
        inner.stroke()
    }

    private func drawGlyph(pressed: Bool) {
        // The progress dots need a smaller font; pressing lowers every glyph one point.
        let text = progress.icon
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.serif(progress == .inProgress ? 16 : 18, bold: true),
            .foregroundColor: isFocused ? NSColor(hex: 0x503007) : NSColor(hex: 0xd7ad60),
            .shadow: Theme.shadow(isFocused ? NSColor(hex: 0xfff2b4, alpha: 0.55) : .black, blur: 1)
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: NSPoint(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2 + (pressed ? -1 : 0)), withAttributes: attributes)
    }
}
