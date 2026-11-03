import AppKit

@MainActor
final class QuestListButton: NSButton {
    let quest: Quest
    var selected = false
    var actionHandler: (() -> Void)?

    init(quest: Quest, selected: Bool, action: @escaping () -> Void) {
        self.quest = quest
        self.selected = selected
        actionHandler = action
        super.init(frame: .zero)
        isBordered = false
        title = quest.title
        target = self
        self.action = #selector(activate)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 62).isActive = true
        toolTip = "[\(quest.priority)] \(quest.title)"
        setAccessibilityLabel(
            L10n.text(
                "quest_list_accessibility", quest.title,
                quest.priority, String(quest.completedCount),
                String(quest.objectives.count)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func activate() {
        actionHandler?()
    }

    override func draw(_ dirtyRect: NSRect) {
        drawSelection()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        drawHeading(paragraph: paragraph)
        drawProgress(paragraph: paragraph)
    }

    // MARK: - Drawing

    private func drawSelection() {
        if selected || cell?.isHighlighted == true {
            NSGradient(colors: [NSColor(hex: 0x62552b, alpha: 0.65), NSColor(hex: 0x282819, alpha: 0.25)])!
                .draw(in: bounds.insetBy(dx: 4, dy: 2), angle: 0)
            Theme.mutedGold.withAlphaComponent(0.5).setStroke()
            NSBezierPath(rect: bounds.insetBy(dx: 4.5, dy: 2.5)).stroke()
        }
    }

    private func drawHeading(paragraph: NSParagraphStyle) {
        // Reserve the left 32 points for the badge and the right 15 for padding.
        // The title and progress occupy separate baselines within the 62-point row.
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.decorative(13), .foregroundColor: Theme.color(quest.severity),
            .paragraphStyle: paragraph, .shadow: Theme.shadow()
        ]
        let markAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.serif(17, bold: true), .foregroundColor: Theme.gold, .shadow: Theme.shadow()
        ]
        ((quest.isComplete ? "✓" : quest.progress.icon) as NSString).draw(
            at: NSPoint(x: 13, y: 29), withAttributes: markAttrs)
        ("[\(quest.displayPriority)] \(quest.title)" as NSString).draw(
            in: NSRect(x: 32, y: 31, width: bounds.width - 47, height: 20), withAttributes: titleAttrs)
    }

    private func drawProgress(paragraph: NSParagraphStyle) {
        let progressAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.serif(10), .foregroundColor: NSColor(hex: 0xaba391), .paragraphStyle: paragraph
        ]
        let progress = progressText
        (progress as NSString).draw(
            in: NSRect(x: 32, y: 12, width: bounds.width - 47, height: 16), withAttributes: progressAttrs)
    }

    private var progressText: String {
        if quest.isComplete { return L10n.text("quest_turned_in") }
        if quest.canTurnIn { return L10n.text("all_objectives_completed_turn_in_quest") }
        return L10n.text(
            "quest_objectives_progress", String(quest.completedCount), String(quest.objectives.count))
    }
}
