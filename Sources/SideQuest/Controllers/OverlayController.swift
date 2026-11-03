import AppKit

@MainActor
final class OverlayController: NSObject, NSWindowDelegate {
    let panel: OverlayPanel
    var openJournal: (() -> Void)?
    var openQuestJournal: ((UUID) -> Void)?

    private let store: QuestStore
    // A narrow desktop column leaves room for the foreground app.
    private let width: CGFloat = 340
    // Fixed header height also determines the collapsed panel height.
    private let headerHeight: CGFloat = 38
    private var isRebuilding = false

    init(store: QuestStore) {
        self.store = store
        // The temporary height is replaced by the first content layout below.
        panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        setUpPanel()
        setUpObservers()
        rebuild()
        restorePosition()

        if store.settings.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func toggleVisibility() {
        store.updateSettings { $0.isVisible.toggle() }
    }

    func resetPosition() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        // Leave breathing room below the menu bar and beside the screen edge.
        panel.setFrameOrigin(
            NSPoint(
                x: visible.maxX - width - 28,
                y: visible.maxY - panel.frame.height - 55
            ))
        savePosition()
    }

    func rebuild() {
        isRebuilding = true
        defer { isRebuilding = false }

        // Preserve the top edge when rows expand, growth should move downward.
        let top = panel.frame.maxY
        let quests = store.activeQuests
        let collapsed = store.settings.isCollapsed
        let surface = SurfaceView(.overlay)
        surface.opacity = store.settings.opacity
        panel.contentView = surface

        let header = makeHeader(in: surface, questCount: quests.count, collapsed: collapsed)
        let contentHeight = collapsed ? 0 : addQuestList(quests, to: surface, below: header)
        resizePanel(contentHeight: contentHeight, top: top)
        surface.layoutSubtreeIfNeeded()
        updateVisibility()
    }

    // MARK: - Window delegate

    func windowDidMove(_ notification: Notification) {
        savePosition()
    }

    // MARK: - Panel setup

    private func setUpPanel() {
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.title = L10n.text("quest_tracker")
        panel.delegate = self
    }

    private func setUpObservers() {
        _ = store.observe { [weak self] in
            self?.rebuild()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func updateVisibility() {
        if store.settings.isVisible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func resizePanel(contentHeight: CGFloat, top: CGFloat) {
        // Use a conservative height before AppKit has assigned the panel a screen.
        let maxHeight = (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        // Cap the tracker at 72% of the usable screen; overflow stays scrollable.
        let height = min(headerHeight + contentHeight, maxHeight * 0.72)
        panel.setFrame(
            NSRect(x: panel.frame.minX, y: top - height, width: width, height: height),
            display: true
        )
    }

    // MARK: - Panel position

    private func restorePosition() {
        if let x = store.settings.originX, let y = store.settings.originY {
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            keepOnScreen()
        } else {
            resetPosition()
        }
    }

    @objc private func screensChanged() {
        keepOnScreen()
    }

    private func keepOnScreen() {
        // Prefer the display containing most of the panel, then clamp its origin
        // to that display after a monitor is removed or its resolution changes.
        let screens = NSScreen.screens
        guard
            let screen = screens.max(by: {
                $0.visibleFrame.intersection(panel.frame).size.area
                    < $1.visibleFrame.intersection(panel.frame).size.area
            })
        else { return }

        let visible = screen.visibleFrame
        var origin = panel.frame.origin
        origin.x = min(max(origin.x, visible.minX), visible.maxX - panel.frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - panel.frame.height)
        panel.setFrameOrigin(origin)
        savePosition()
    }

    private func savePosition() {
        // Resizing also emits move notifications; only persist user-driven moves.
        guard !isRebuilding else { return }
        let origin = panel.frame.origin
        store.updateSettings(
            {
                $0.originX = origin.x
                $0.originY = origin.y
            }, notify: false)
    }

    // MARK: - Header

    private func makeHeader(in surface: NSView, questCount: Int, collapsed: Bool) -> DragHeader {
        let header = DragHeader()
        header.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(header)

        let title = Theme.label(L10n.text("quests"), size: 16, bold: true, decorative: true)
        title.shadow = Theme.shadow()
        header.addSubview(title)

        let count = Theme.label("(\(questCount))", size: 12, color: Theme.mutedGold)
        header.addSubview(count)

        let journal = GameButton("⚙", style: .subtle) { [weak self] in
            self?.openJournal?()
        }
        journal.toolTip = L10n.text("open_quest_journal")
        journal.setAccessibilityLabel(L10n.text("open_quest_journal"))
        header.addSubview(journal)

        let collapse = GameButton(collapsed ? "+" : "−", style: .dark) { [weak store] in
            store?.updateSettings { $0.isCollapsed.toggle() }
        }
        collapse.toolTip = collapsed ? L10n.text("expand_tracker") : L10n.text("collapse_tracker")
        header.addSubview(collapse)

        // Compact controls leave a broad draggable area around the title.
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: surface.topAnchor),
            header.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: headerHeight),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            count.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 7),
            count.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            collapse.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            collapse.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            collapse.widthAnchor.constraint(equalToConstant: 18),
            collapse.heightAnchor.constraint(equalToConstant: 18),
            journal.trailingAnchor.constraint(equalTo: collapse.leadingAnchor, constant: -8),
            journal.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            journal.widthAnchor.constraint(equalToConstant: 24),
            journal.heightAnchor.constraint(equalToConstant: 24)
        ])

        return header
    }

    // MARK: - Quest list

    private func addQuestList(_ quests: [Quest], to surface: NSView, below header: NSView) -> CGFloat {
        let rule = Theme.separator()
        surface.addSubview(rule)
        NSLayoutConstraint.activate([
            rule.topAnchor.constraint(equalTo: header.bottomAnchor),
            rule.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 11),
            rule.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -11)
        ])

        let stack = makeQuestStack(quests)
        addScrollView(for: stack, to: surface, below: rule)
        surface.layoutSubtreeIfNeeded()
        // The empty state needs room for its message and button; populated lists
        // keep at least 50 points even before their first full layout pass.
        return quests.isEmpty ? 96 : max(50, stack.fittingSize.height)
    }

    private func makeQuestStack(_ quests: [Quest]) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 12, bottom: 16, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        if quests.isEmpty {
            addEmptyState(to: stack)
        } else {
            for quest in quests {
                let row = makeRow(quest)
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(
                    equalTo: stack.widthAnchor, constant: -(stack.edgeInsets.left + stack.edgeInsets.right)
                ).isActive = true
            }
        }

        return stack
    }

    private func addEmptyState(to stack: NSStackView) {
        let empty = Theme.label(
            L10n.text("no_active_quests"),
            size: 14,
            color: NSColor(hex: 0xe3d8be)
        )
        stack.addArrangedSubview(empty)

        let create = GameButton(L10n.text("add_quest"), style: .dark) { [weak self] in
            self?.openJournal?()
        }
        create.heightAnchor.constraint(equalToConstant: 27).isActive = true
        create.widthAnchor.constraint(equalToConstant: 150).isActive = true
        stack.addArrangedSubview(create)
    }

    private func addScrollView(for stack: NSStackView, to surface: NSView, below rule: NSView) {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        surface.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: rule.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
    }

    // MARK: - Quest row

    private func makeRow(_ quest: Quest) -> NSView {
        let row = NSStackView()
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 6

        let heading = makeQuestHeading(quest)
        row.addArrangedSubview(heading)
        heading.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true

        if quest.isExpanded {
            let objectiveRow = makeObjectiveRow(quest)
            row.addArrangedSubview(objectiveRow)
            objectiveRow.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
            row.addArrangedSubview(makeProgressRow(quest))
        }

        return row
    }

    private func makeQuestHeading(_ quest: Quest) -> NSStackView {
        let heading = NSStackView()
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 6
        heading.addArrangedSubview(makeStatusBadge(quest))
        heading.addArrangedSubview(makeQuestTitle(quest))
        heading.addArrangedSubview(makeExpandButton(quest))
        return heading
    }

    private func makeStatusBadge(_ quest: Quest) -> QuestStatusBadgeButton {
        let isFocused = store.focusedQuestID == quest.id
        let badge = QuestStatusBadgeButton(progress: quest.progress, isFocused: isFocused) { [weak store] in
            store?.toggleFocus(quest.id)
        }
        let focusHint =
            isFocused
            ? L10n.text("currently_focused_quest_click_to_clear_selection")
            : L10n.text("click_to_focus_on_this_quest")
        badge.setAccessibilityLabel(
            L10n.text(
                "overlay_quest_accessibility",
                quest.title,
                quest.progress.title,
                quest.priority,
                focusHint
            ))
        return badge
    }

    private func makeExpandButton(_ quest: Quest) -> GameButton {
        let expand = GameButton(quest.isExpanded ? "▾" : "▸", style: .subtle) { [weak store] in
            store?.toggleExpanded(quest.id)
        }
        expand.font = .systemFont(ofSize: 12)
        expand.widthAnchor.constraint(equalToConstant: 13).isActive = true
        expand.heightAnchor.constraint(equalToConstant: 19).isActive = true
        expand.toolTip = L10n.text("expand_or_collapse_quest")
        return expand
    }

    private func makeQuestTitle(_ quest: Quest) -> NSTextField {
        let title = NSTextField(wrappingLabelWithString: "[\(quest.displayPriority)] \(quest.title)")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = Theme.decorative(14)
        title.textColor = Theme.color(quest.severity)
        title.shadow = Theme.shadow(blur: 2)
        title.toolTip = L10n.text(
            "quest_priority_tooltip",
            quest.priority,
            quest.title
        )
        // Keep a long title from crowding out the rest of the tracker.
        title.maximumNumberOfLines = 3
        return title
    }

    // MARK: - Objectives and progress

    private func makeObjectiveRow(_ quest: Quest) -> NSStackView {
        let objectiveRow = NSStackView()
        objectiveRow.orientation = .horizontal
        objectiveRow.alignment = .top
        objectiveRow.spacing = 7
        // Align the objective checkbox after the 30-point badge and 6-point gap.
        objectiveRow.edgeInsets = NSEdgeInsets(top: 0, left: 36, bottom: 0, right: 3)

        if let objective = quest.currentObjective {
            addObjective(objective, for: quest, to: objectiveRow)
        } else if quest.canTurnIn {
            addTurnInAction(for: quest, to: objectiveRow)
        } else {
            let hint = Theme.label(
                L10n.text("add_objectives_in_the_quest_journal"),
                size: 11,
                color: Theme.mutedGold
            )
            objectiveRow.addArrangedSubview(hint)
        }

        return objectiveRow
    }

    private func addObjective(_ objective: Objective, for quest: Quest, to objectiveRow: NSStackView) {
        let check = GameButton(L10n.text("complete_objective"), style: .checkbox) { [weak store] in
            store?.toggleObjective(questID: quest.id, objectiveID: objective.id)
        }
        check.toolTip = L10n.text("complete_value", objective.title)
        check.widthAnchor.constraint(equalToConstant: 14).isActive = true
        check.heightAnchor.constraint(equalToConstant: 14).isActive = true
        objectiveRow.addArrangedSubview(check)

        let text = NSTextField(wrappingLabelWithString: objective.title)
        text.font = Theme.serif(12)
        text.textColor = NSColor(hex: 0xe9e2cf)
        // Full objective text remains available in the tooltip and journal.
        text.maximumNumberOfLines = 4
        text.shadow = Theme.shadow()
        text.toolTip = objective.title
        objectiveRow.addArrangedSubview(text)
    }

    private func addTurnInAction(for quest: Quest, to objectiveRow: NSStackView) {
        objectiveRow.alignment = .centerY
        objectiveRow.addArrangedSubview(Theme.label(L10n.text("ready_to_turn_in_hint"), size: 11))
        let open = GameButton(L10n.text("open_journal"), style: .dark) { [weak self] in
            self?.openQuestJournal?(quest.id)
        }
        open.font = Theme.serif(10)
        open.widthAnchor.constraint(equalToConstant: 120).isActive = true
        open.heightAnchor.constraint(equalToConstant: 24).isActive = true
        objectiveRow.addArrangedSubview(open)
    }

    private func makeProgressRow(_ quest: Quest) -> NSStackView {
        let progress = Theme.label(
            L10n.text(
                "overlay_progress",
                String(quest.completedCount),
                String(quest.objectives.count)
            ),
            size: 10,
            color: Theme.mutedGold
        )
        let progressRow = NSStackView(views: [progress])
        // Align progress with objective text: badge (30), gap (6), checkbox (14), gap (7).
        progressRow.edgeInsets = NSEdgeInsets(top: 0, left: 57, bottom: 0, right: 0)
        return progressRow
    }
}

// MARK: - Overlay panel

@MainActor
final class OverlayPanel: NSPanel {
    // Tracker clicks must not take keyboard focus away from the foreground app.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Drag header

@MainActor
final class DragHeader: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

// MARK: - Screen intersection area

private extension NSSize {
    var area: CGFloat { max(0, width) * max(0, height) }
}
