import AppKit

@MainActor
final class GameTextField: NSTextField {
    init(placeholder: String = "", value: String = "", size: CGFloat = 14) {
        super.init(frame: .zero)
        stringValue = value
        placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.gray,
                .font: Theme.serif(size)
            ]
        )
        font = Theme.serif(size)
        textColor = Theme.ink
        backgroundColor = Theme.textField
        isBezeled = true
        bezelStyle = .squareBezel
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        cell?.isScrollable = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
