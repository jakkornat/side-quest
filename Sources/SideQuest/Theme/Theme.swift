import AppKit

/// Shared palette, typography and controls for the journal and desktop tracker.
@MainActor
enum Theme {

    // MARK: - Colors
    static let gold = NSColor(hex: 0xe9c96b)
    static let mutedGold = NSColor(hex: 0x9e8953)
    static let ink = NSColor(hex: 0x382211)
    static let parchment = NSColor(hex: 0xd8b97b)
    static let stone = NSColor(hex: 0x171919)
    static let red = NSColor(hex: 0x681711)
    static let textField = NSColor(hex: 0xf2d69b, alpha: 0.5)

    // MARK: - Fonts
    static func serif(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: BundledFonts.metamorphousPostScriptName, size: size) ?? .systemFont(ofSize: size)
    }

    static func decorative(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? BundledFonts.boldName : BundledFonts.regularName, size: size)
            ?? serif(size, bold: bold)
    }

    /// Maps quest difficulty to its heading and badge color.
    static func color(_ severity: Severity) -> NSColor {
        switch severity {
        case .trivial: NSColor(hex: 0xf4f0e5)
        case .normal: NSColor(hex: 0x62db40)
        case .important: NSColor(hex: 0xffdc42)
        case .urgent: NSColor(hex: 0xff922d)
        case .critical: NSColor(hex: 0xff4843)
        }
    }

    /// Creates a non-editable label ready for Auto Layout.
    static func label(
        _ text: String, size: CGFloat = 13, color: NSColor = gold, bold: Bool = false,
        decorative: Bool = false
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = decorative ? self.decorative(size, bold: bold) : serif(size, bold: bold)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    /// Get a 1px height separator with color
    static func separator(color: NSColor = mutedGold) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = color.withAlphaComponent(0.55).cgColor
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    /// A one-point downward shadow separates lettering from textured surfaces.
    static func shadow(_ color: NSColor = .black, blur: CGFloat = 2) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        return shadow
    }

    /// Shared eight-point text inset and minimum fitted button font size.
    static func margin() -> CGFloat { 8 }
}
