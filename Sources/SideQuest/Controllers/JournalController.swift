import AppKit

@MainActor
final class JournalController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    let window: NSWindow
    var toggleOverlay: (() -> Void)?
    var resetOverlay: (() -> Void)?
    private let store: QuestStore

    // Persistent views shared by the sidebar and editor.
    private let listStack = NSStackView()
    private let parchment = SurfaceView(.parchment)
    private let pageStack = NSStackView()
    private let activeButton = GameButton(L10n.text("active"), style: .dark)
    private let completedButton = GameButton(L10n.text("completed"), style: .dark)
    private let overlayButton = GameButton(L10n.text("hide_overlay"), style: .dark)
    private let statusLabel = Theme.label("", size: 10, color: Theme.mutedGold)
    private let saveButton = GameButton(L10n.text("save_quest"))
    private let deleteButton = GameButton(L10n.text("abandon_quest"), style: .dark)

    // The draft stays separate from the store until validation succeeds.
    private var showCompleted = false
    private var selectedID: UUID?
    private var draft: Quest?
    private var isDirty = false

    // Replaced whenever the editor is rebuilt.
    private var nameField: GameTextField?
    private var priorityField: GameTextField?
    private var objectiveFields: [UUID: GameTextField] = [:]
    private var validationLabel: NSTextField?
    private var severityButtons: [Severity: GameButton] = [:]
    private var questActionButton: GameButton?
    private var questActionHint: NSTextField?

    init(store: QuestStore) {
        self.store = store
        // Start large enough for the fixed sidebar and the full quest form.
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 690),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init()
        setUpWindow()
        buildChrome()
        if let first = store.activeQuests.first {
            selectedID = first.id
            draft = first
        }
        refreshSidebar()
        renderEditor()
        _ = store.observe { [weak self] in self?.storeChanged() }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func showQuest(_ id: UUID) {
        guard let quest = store.quests.first(where: { $0.id == id }) else {
            show()
            return
        }
        select(quest)
        showCompleted = draft?.isComplete ?? false
        refreshSidebar()
        show()
    }

    func createQuest() {
        guard commitBeforeNavigation() else { return }
        showCompleted = false
        selectedID = nil
        draft = Quest(title: "", objectives: [Objective(title: "")])
        isDirty = false
        refreshSidebar()
        renderEditor()
        show()
        window.makeFirstResponder(nameField)
    }

    // MARK: - Window layout

    private func setUpWindow() {
        window.title = L10n.text("quest_journal")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.stone
        // Below this size the footer actions and difficulty choices would overlap.
        window.minSize = NSSize(width: 820, height: 590)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("SideQuestJournalWindow")
        window.center()
    }

    private func buildChrome() {
        let root = SurfaceView(.frame)
        window.contentView = root
        let title = Theme.label(
            L10n.text("quest_journal"), size: 17, color: NSColor(hex: 0xe8dfc4), decorative: true)
        title.shadow = Theme.shadow()
        root.addSubview(title)
        let separator = Theme.separator()
        root.addSubview(separator)
        let left = SurfaceView(.stone)
        root.addSubview(left)
        root.addSubview(parchment)

        buildSidebar(in: left)
        buildPageScrollView()
        buildFooter(in: root, below: left)

        // The sidebar stays fixed; the parchment takes the remaining width.
        // Reserve 65 points below both panels for actions and the status line.
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            title.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            separator.topAnchor.constraint(equalTo: root.topAnchor, constant: 42),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            left.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            left.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            left.widthAnchor.constraint(equalToConstant: 292),
            left.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -65),
            parchment.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 8),
            parchment.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            parchment.topAnchor.constraint(equalTo: left.topAnchor),
            parchment.bottomAnchor.constraint(equalTo: left.bottomAnchor)
        ])
    }

    private func buildSidebar(in left: NSView) {
        let tabs = NSStackView(views: [activeButton, completedButton])
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.spacing = 6
        tabs.distribution = .fillEqually
        left.addSubview(tabs)
        activeButton.actionHandler = { [weak self] in self?.switchFilter(completed: false) }
        completedButton.actionHandler = { [weak self] in self?.switchFilter(completed: true) }
        let listRule = Theme.separator()
        left.addSubview(listRule)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        left.addSubview(scroll)
        
        let listDocument = FlippedView()
        listDocument.translatesAutoresizingMaskIntoConstraints = false
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 3
        listStack.edgeInsets = NSEdgeInsets(top: 6, left: 5, bottom: 8, right: 5)
        listDocument.addSubview(listStack)
        
        scroll.documentView = listDocument
        let sort = Theme.label(
            L10n.text("higher_priority_higher_on_the_list"), size: 9, color: Theme.mutedGold)
        sort.alignment = .center
        left.addSubview(sort)

        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 12),
            tabs.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -12),
            tabs.topAnchor.constraint(equalTo: left.topAnchor, constant: 12),
            tabs.heightAnchor.constraint(equalToConstant: 27),
            listRule.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 10),
            listRule.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 9),
            listRule.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -9),
            scroll.topAnchor.constraint(equalTo: listRule.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -4),
            scroll.bottomAnchor.constraint(equalTo: sort.topAnchor, constant: -9),
            sort.bottomAnchor.constraint(equalTo: left.bottomAnchor, constant: -12),
            sort.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 5),
            sort.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -5),
            listDocument.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            listStack.leadingAnchor.constraint(equalTo: listDocument.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: listDocument.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: listDocument.topAnchor),
            listStack.bottomAnchor.constraint(equalTo: listDocument.bottomAnchor)
        ])
    }

    private func buildPageScrollView() {
        // Insets leave the parchment border visible and frame the page text.
        let pageScroll = NSScrollView()
        pageScroll.translatesAutoresizingMaskIntoConstraints = false
        pageScroll.drawsBackground = false
        pageScroll.hasVerticalScroller = true
        pageScroll.autohidesScrollers = true
        pageScroll.scrollerStyle = .overlay
        parchment.addSubview(pageScroll)
        let pageDocument = FlippedView()
        pageDocument.translatesAutoresizingMaskIntoConstraints = false
        pageStack.translatesAutoresizingMaskIntoConstraints = false
        pageStack.orientation = .vertical
        pageStack.alignment = .leading
        pageStack.spacing = 11
        pageStack.edgeInsets = NSEdgeInsets(top: 27, left: 29, bottom: 25, right: 29)
        pageDocument.addSubview(pageStack)
        pageScroll.documentView = pageDocument

        NSLayoutConstraint.activate([
            pageScroll.leadingAnchor.constraint(equalTo: parchment.leadingAnchor, constant: 5),
            pageScroll.trailingAnchor.constraint(equalTo: parchment.trailingAnchor, constant: -5),
            pageScroll.topAnchor.constraint(equalTo: parchment.topAnchor, constant: 5),
            pageScroll.bottomAnchor.constraint(equalTo: parchment.bottomAnchor, constant: -5),
            pageDocument.widthAnchor.constraint(equalTo: pageScroll.contentView.widthAnchor),
            pageStack.leadingAnchor.constraint(equalTo: pageDocument.leadingAnchor),
            pageStack.trailingAnchor.constraint(equalTo: pageDocument.trailingAnchor),
            pageStack.topAnchor.constraint(equalTo: pageDocument.topAnchor),
            pageStack.bottomAnchor.constraint(equalTo: pageDocument.bottomAnchor)
        ])
    }

    private func buildFooter(in root: NSView, below left: NSView) {
        // All footer buttons are 28 points high. Widths accommodate the localized
        // labels while keeping the left actions within the sidebar column.
        let newButton = GameButton(L10n.text("add_new_quest")) { [weak self] in self?.createQuest() }
        newButton.keyEquivalent = "n"
        newButton.keyEquivalentModifierMask = .command
        root.addSubview(newButton)
        root.addSubview(overlayButton)
        overlayButton.actionHandler = { [weak self] in self?.toggleOverlay?() }
        let settingsButton = GameButton("⚙", style: .dark) { [weak self] in self?.showSettings() }
        settingsButton.setAccessibilityLabel(L10n.text("overlay_settings"))
        settingsButton.toolTip = L10n.text("overlay_settings")
        root.addSubview(settingsButton)
        root.addSubview(deleteButton)
        deleteButton.actionHandler = { [weak self] in self?.deleteQuest() }
        root.addSubview(saveButton)
        saveButton.actionHandler = { [weak self] in self?.saveDraft() }
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = .command
        root.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            newButton.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            newButton.topAnchor.constraint(equalTo: left.bottomAnchor, constant: 12),
            newButton.widthAnchor.constraint(equalToConstant: 130),
            newButton.heightAnchor.constraint(equalToConstant: 28),
            overlayButton.leadingAnchor.constraint(equalTo: newButton.trailingAnchor, constant: 8),
            overlayButton.centerYAnchor.constraint(equalTo: newButton.centerYAnchor),
            overlayButton.widthAnchor.constraint(equalToConstant: 124),
            overlayButton.heightAnchor.constraint(equalToConstant: 28),
            settingsButton.leadingAnchor.constraint(equalTo: overlayButton.trailingAnchor, constant: 6),
            settingsButton.centerYAnchor.constraint(equalTo: newButton.centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 26),
            settingsButton.heightAnchor.constraint(equalToConstant: 28),
            saveButton.trailingAnchor.constraint(equalTo: parchment.trailingAnchor),
            saveButton.centerYAnchor.constraint(equalTo: newButton.centerYAnchor),
            saveButton.widthAnchor.constraint(equalToConstant: 136),
            saveButton.heightAnchor.constraint(equalToConstant: 28),
            deleteButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 124),
            deleteButton.heightAnchor.constraint(equalToConstant: 28),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 15),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -15),
            statusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8)
        ])
    }

    // MARK: - Store updates and selection

    private func storeChanged() {
        refreshSidebar()
        guard let id = selectedID else {
            updateStatus()
            return
        }
        if let latest = store.quests.first(where: { $0.id == id }) {
            if !isDirty && draft != latest {
                draft = latest
                renderEditor()
            } else if isDirty {
                mergeCompletion(from: latest)
                updateQuestAction()
            }
        } else {
            selectedID = nil
            draft = nil
            isDirty = false
            renderEditor()
        }
        updateStatus()
    }

    private func mergeCompletion(from latest: Quest) {
        guard var draft else { return }

        // Match by ID: the user may have reordered the draft while completing
        // objectives in the desktop tracker. Keep all unsaved text and ordering.
        for index in draft.objectives.indices {
            let id = draft.objectives[index].id
            if let objective = latest.objectives.first(where: { $0.id == id }) {
                draft.objectives[index].isComplete = objective.isComplete
            }
        }
        draft.completedAt = latest.completedAt
        self.draft = draft
    }

    private func refreshSidebar() {
        listStack.arrangedSubviews.forEach {
            listStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        activeButton.title = L10n.text("active_value", String(store.activeQuests.count))
        completedButton.title = L10n.text("completed_value", String(store.completedQuests.count))
        activeButton.isSelected = !showCompleted
        completedButton.isSelected = showCompleted
        activeButton.needsDisplay = true
        completedButton.needsDisplay = true
        overlayButton.title = store.settings.isVisible ? L10n.text("hide_overlay") : L10n.text("show_overlay")
        overlayButton.needsDisplay = true
        let quests = showCompleted ? store.completedQuests : store.activeQuests
        if quests.isEmpty {
            let text = NSTextField(
                wrappingLabelWithString: showCompleted
                    ? L10n.text("completed_list_empty") : L10n.text("active_list_empty"))
            text.font = Theme.serif(12)
            text.textColor = Theme.mutedGold
            text.alignment = .center
            listStack.addArrangedSubview(text)
            text.widthAnchor.constraint(
                equalTo: listStack.widthAnchor,
                constant: -(listStack.edgeInsets.left + listStack.edgeInsets.right)
            ).isActive = true
            // Allow two lines and vertical breathing room in an otherwise empty list.
            text.heightAnchor.constraint(equalToConstant: 94).isActive = true
        } else {
            for quest in quests {
                let button = QuestListButton(quest: quest, selected: quest.id == selectedID) { [weak self] in
                    self?.select(quest)
                }
                listStack.addArrangedSubview(button)
                button.widthAnchor.constraint(
                    equalTo: listStack.widthAnchor,
                    constant: -(listStack.edgeInsets.left + listStack.edgeInsets.right)
                ).isActive = true
            }
        }
        updateStatus()
    }

    private func select(_ quest: Quest) {
        guard selectedID != quest.id, commitBeforeNavigation() else { return }
        selectedID = quest.id
        draft = store.quests.first(where: { $0.id == quest.id }) ?? quest
        isDirty = false
        refreshSidebar()
        renderEditor()
    }

    private func switchFilter(completed: Bool) {
        guard commitBeforeNavigation() else { return }
        showCompleted = completed
        let quests = completed ? store.completedQuests : store.activeQuests
        selectedID = quests.first?.id
        draft = quests.first
        isDirty = false
        refreshSidebar()
        renderEditor()
    }

    // MARK: - Editor layout

    private func addPage(_ view: NSView, fullWidth: Bool = true) {
        pageStack.addArrangedSubview(view)
        if fullWidth {
            view.widthAnchor.constraint(
                equalTo: pageStack.widthAnchor,
                constant: -(pageStack.edgeInsets.left + pageStack.edgeInsets.right)
            ).isActive = true
        }
    }

    private func renderEditor() {
        clearEditor()
        saveButton.isEnabled = draft != nil
        deleteButton.isEnabled = selectedID != nil
        guard let quest = draft else {
            renderEmptyPage()
            return
        }

        addQuestHeading(quest)
        addNameField(quest)
        addPriorityField(quest)
        addSeverityPicker(quest)
        addObjectives(quest)
        addValidationMessage()
        addQuestAction(quest)

        window.contentView?.layoutSubtreeIfNeeded()
        updateStatus()
    }

    private func clearEditor() {
        pageStack.arrangedSubviews.forEach {
            pageStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        objectiveFields.removeAll()
        severityButtons.removeAll()
        nameField = nil
        priorityField = nil
        validationLabel = nil
        questActionButton = nil
        questActionHint = nil
    }

    private func editorHeading(for quest: Quest) -> String {
        if selectedID == nil { return L10n.text("new_adventure") }
        if quest.isComplete { return L10n.text("quest_turned_in_heading") }
        if quest.canTurnIn { return L10n.text("ready_to_turn_in_heading") }
        return L10n.text("adventure_journal")
    }

    private func addQuestHeading(_ quest: Quest) {
        let kicker = Theme.label(
            editorHeading(for: quest), size: 10, color: NSColor(hex: 0x6e4b21), bold: true, decorative: true
        )
        addPage(kicker)
        let heading = Theme.label(
            selectedID == nil ? L10n.text("new_quest") : quest.title, size: 24, color: Theme.ink, bold: true,
            decorative: true)
        heading.maximumNumberOfLines = 2
        heading.lineBreakMode = .byWordWrapping
        addPage(heading)
        addPage(Theme.separator(color: Theme.ink))
    }

    private func addNameField(_ quest: Quest) {
        addPage(Theme.label(L10n.text("quest_name_heading"), size: 10, color: Theme.ink, bold: true))
        let name = GameTextField(placeholder: L10n.text("name_your_adventure"), value: quest.title, size: 17)
        name.delegate = self
        name.setAccessibilityLabel(L10n.text("quest_name"))
        name.heightAnchor.constraint(equalToConstant: 32).isActive = true
        nameField = name
        addPage(name)
    }

    private func addPriorityField(_ quest: Quest) {
        let priorityRow = NSStackView()
        priorityRow.orientation = .horizontal
        priorityRow.spacing = 14
        let priorityTitle = Theme.label(L10n.text("priority"), size: 10, color: Theme.ink, bold: true)
        let priority = GameTextField(placeholder: L10n.text("any_integer"), value: quest.priority, size: 13)
        priority.delegate = self
        priority.setAccessibilityLabel(L10n.text("priority_any_integer"))
        priority.heightAnchor.constraint(equalToConstant: 28).isActive = true
        priorityField = priority
        priorityRow.addArrangedSubview(priorityTitle)
        priorityRow.addArrangedSubview(priority)
        priorityTitle.widthAnchor.constraint(equalToConstant: 80).isActive = true
        addPage(priorityRow)
    }

    private func addSeverityPicker(_ quest: Quest) {
        addPage(Theme.label(L10n.text("quest_difficulty"), size: 10, color: Theme.ink, bold: true))
        let severityRow = NSStackView()
        severityRow.spacing = 5
        severityRow.distribution = .fillEqually
        for severity in Severity.allCases {
            let button = GameButton(severity.title, style: .dark) { [weak self] in
                self?.draft?.severity = severity
                self?.isDirty = true
                self?.updateSeverity()
                self?.updateStatus()
            }
            button.font = Theme.serif(10)
            button.tint = Theme.color(severity)
            button.isSelected = severity == quest.severity
            button.heightAnchor.constraint(equalToConstant: 29).isActive = true
            // Difficulty is stored from zero; announce levels starting at one.
            button.setAccessibilityLabel(
                L10n.text(
                    "severity_accessibility", String(severity.rawValue + 1),
                    severity.title))
            severityButtons[severity] = button
            severityRow.addArrangedSubview(button)
        }
        addPage(severityRow)
        let hint = Theme.label(L10n.text("severity_levels"), size: 9, color: NSColor(hex: 0x70522c))
        addPage(hint)
    }

    private func addObjectives(_ quest: Quest) {
        addPage(Theme.separator(color: Theme.ink))
        addPage(
            Theme.label(
                L10n.text("quest_objectives"), size: 16, color: Theme.ink, bold: true, decorative: true))
        let description = NSTextField(
            wrappingLabelWithString: L10n.text(
                "the_overlay_shows_the_first_incomplete_objective_in_the_order_of_this_list"))
        description.font = Theme.serif(11)
        description.textColor = NSColor(hex: 0x70522c)
        addPage(description)
        for (index, objective) in quest.objectives.enumerated() {
            addPage(makeObjectiveRow(objective, index: index))
        }
        let add = GameButton(L10n.text("add_another_objective"), style: .dark) { [weak self] in
            self?.addObjective()
        }
        add.heightAnchor.constraint(equalToConstant: 27).isActive = true
        add.widthAnchor.constraint(equalToConstant: 170).isActive = true
        addPage(add, fullWidth: false)
    }

    private func addValidationMessage() {
        let validation = NSTextField(wrappingLabelWithString: "")
        validation.font = Theme.serif(11)
        validation.textColor = NSColor(hex: 0x8d1f16)
        validationLabel = validation
        addPage(validation)
    }

    private func addQuestAction(_ quest: Quest) {
        guard selectedID != nil else { return }

        addPage(Theme.separator(color: Theme.ink))
        let progress = Theme.label(
            L10n.text(
                "progress_value_value_objectives", String(quest.completedCount),
                String(quest.objectives.count)), size: 10, color: Theme.ink, bold: true)
        addPage(progress)
        let hint = NSTextField(wrappingLabelWithString: "")
        hint.font = Theme.serif(11)
        hint.textColor = NSColor(hex: 0x70522c)
        questActionHint = hint
        addPage(hint)
        let complete = GameButton(
            quest.isComplete ? L10n.text("resume_quest") : L10n.text("turn_in_quest"),
            style: quest.isComplete ? .dark : .red
        ) { [weak self] in self?.performQuestAction() }
        questActionButton = complete
        complete.widthAnchor.constraint(equalToConstant: 195).isActive = true
        complete.heightAnchor.constraint(equalToConstant: 28).isActive = true
        addPage(complete, fullWidth: false)
        updateQuestAction()
    }

    private func renderEmptyPage() {
        // A 48-point top gap and large seal give the empty page a centered composition.
        let space = NSView()
        space.heightAnchor.constraint(equalToConstant: 48).isActive = true
        addPage(space)
        let seal = Theme.label("!", size: 76, color: NSColor(hex: 0x785224), bold: true)
        seal.alignment = .center
        addPage(seal)
        let title = Theme.label(
            showCompleted ? L10n.text("every_adventure_has_an_ending") : L10n.text("adventure_awaits"),
            size: 25, color: Theme.ink, bold: true, decorative: true)
        title.alignment = .center
        title.maximumNumberOfLines = 2
        addPage(title)
        addPage(Theme.separator(color: Theme.ink))
        let text = NSTextField(
            wrappingLabelWithString: showCompleted
                ? L10n.text("completed_journal_intro")
                : L10n.text("active_journal_intro"))
        text.font = Theme.serif(14)
        text.textColor = Theme.ink
        text.alignment = .center
        addPage(text)
        let new = GameButton(L10n.text("start_a_new_quest")) { [weak self] in self?.createQuest() }
        new.heightAnchor.constraint(equalToConstant: 33).isActive = true
        addPage(new)
    }

    private func makeObjectiveRow(_ objective: Objective, index: Int) -> NSView {
        // Compact 20–24 point controls leave most of the row for the objective text.
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        let check = GameButton(
            L10n.text("complete_objective_value", String(index + 1)), style: .checkbox
        ) { [weak self] in self?.toggleObjective(objective.id) }
        check.isSelected = objective.isComplete
        check.widthAnchor.constraint(equalToConstant: 20).isActive = true
        check.heightAnchor.constraint(equalToConstant: 20).isActive = true
        row.addArrangedSubview(check)
        let field = GameTextField(
            placeholder: L10n.text("objective_placeholder", String(index + 1)),
            value: objective.title, size: 12)
        field.delegate = self
        field.textColor = objective.isComplete ? NSColor(hex: 0x8a7049) : Theme.ink
        field.heightAnchor.constraint(equalToConstant: 28).isActive = true
        field.setAccessibilityLabel(L10n.text("objective_accessibility", String(index + 1)))
        objectiveFields[objective.id] = field
        row.addArrangedSubview(field)
        let up = GameButton("↑", style: .dark) { [weak self] in self?.moveObjective(objective.id, by: -1) }
        up.isEnabled = index > 0
        up.toolTip = L10n.text("move_objective_up")
        let down = GameButton("↓", style: .dark) { [weak self] in self?.moveObjective(objective.id, by: 1) }
        down.isEnabled = index < (draft?.objectives.count ?? 0) - 1
        down.toolTip = L10n.text("move_objective_down")
        let remove = GameButton("×", style: .dark) { [weak self] in self?.removeObjective(objective.id) }
        remove.tint = NSColor(hex: 0xf18f76)
        remove.toolTip = L10n.text("remove_objective")
        for button in [up, down, remove] {
            button.widthAnchor.constraint(equalToConstant: 22).isActive = true
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
            row.addArrangedSubview(button)
        }
        return row
    }

    // MARK: - Editing and validation

    func controlTextDidChange(_ obj: Notification) {
        isDirty = true
        readFields()
        updateQuestAction()
        updateStatus()
    }

    private func updateQuestAction() {
        guard let quest = draft, let button = questActionButton else { return }
        button.isEnabled = quest.isComplete || quest.canTurnIn
        if quest.isComplete {
            questActionHint?.stringValue = L10n.text("quest_turned_in_you_can_resume_the_last_objective")
        } else if quest.canTurnIn {
            questActionHint?.stringValue = L10n.text(
                "all_objectives_completed_turn_in_the_quest_to_finish_your_adventure")
        } else if quest.objectives.isEmpty {
            questActionHint?.stringValue = L10n.text(
                "add_and_complete_at_least_one_objective_to_turn_in_the_quest")
        } else {
            questActionHint?.stringValue = L10n.text(
                "you_can_turn_in_the_quest_after_checking_off_all_objectives")
        }
        button.toolTip = questActionHint?.stringValue
    }

    private func readFields() {
        guard var draft else { return }
        if let nameField { draft.title = nameField.stringValue }
        if let priorityField { draft.priority = priorityField.stringValue }

        for index in draft.objectives.indices {
            let id = draft.objectives[index].id
            guard let field = objectiveFields[id] else { continue }
            draft.objectives[index].title = field.stringValue
        }
        self.draft = draft
    }

    private func updateSeverity() {
        for (severity, button) in severityButtons { button.isSelected = severity == draft?.severity }
    }

    private func updateStatus() {
        if let error = store.persistenceError {
            statusLabel.stringValue = error
            statusLabel.textColor = NSColor(hex: 0xff8975)
            statusLabel.toolTip = error
        } else {
            statusLabel.textColor = Theme.mutedGold
            statusLabel.stringValue =
                isDirty
                ? L10n.text("unsaved_changes_s_to_save")
                : L10n.text("saved_locally_n_new_quest_drag_the_tracker_header_to_move_it")
        }
    }

    @discardableResult private func saveDraft() -> Bool {
        window.makeFirstResponder(nil)
        readFields()
        guard var quest = draft else { return true }
        guard !quest.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationLabel?.stringValue = L10n.text("give_your_quest_a_name")
            window.makeFirstResponder(nameField)
            return false
        }
        guard let priority = Priority.normalize(quest.priority) else {
            validationLabel?.stringValue = L10n.text(
                "priority_must_be_an_integer_e_g_1_42_or_1000_there_is_no_value_limit")
            window.makeFirstResponder(priorityField)
            return false
        }
        quest.priority = priority
        let isNewQuest = !store.quests.contains {
            $0.id == quest.id
        }
        isDirty = false
        selectedID = quest.id
        _ = store.save(quest)
        draft = store.quests.first(where: { $0.id == quest.id })
        showCompleted = draft?.isComplete ?? false
        refreshSidebar()
        renderEditor()

        if isNewQuest {
            SoundPlayer.shared.play(sound: .new)
        }
        return true
    }

    private func commitBeforeNavigation() -> Bool {
        guard isDirty else { return true }
        return saveDraft()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        commitBeforeNavigation()
    }

    // MARK: - Objective actions

    private func addObjective() {
        readFields()
        let objective = Objective(title: "")
        draft?.objectives.append(objective)
        isDirty = true
        renderEditor()
        window.makeFirstResponder(objectiveFields[objective.id])
        objectiveFields[objective.id]?.scrollToVisible(objectiveFields[objective.id]?.bounds ?? .zero)
    }

    private func removeObjective(_ id: UUID) {
        readFields()
        draft?.objectives.removeAll { $0.id == id }
        isDirty = true
        renderEditor()
    }

    private func moveObjective(_ id: UUID, by offset: Int) {
        readFields()
        guard let index = draft?.objectives.firstIndex(where: { $0.id == id }),
            let count = draft?.objectives.count, (0..<count).contains(index + offset)
        else { return }
        // Swap adjacent steps so the overlay follows the user-defined objective order.
        draft?.objectives.swapAt(index, index + offset)
        isDirty = true
        renderEditor()
    }

    private func toggleObjective(_ id: UUID) {
        readFields()
        guard let index = draft?.objectives.firstIndex(where: { $0.id == id }) else { return }
        draft?.objectives[index].isComplete.toggle()
        isDirty = true
        if selectedID != nil { _ = saveDraft() } else { renderEditor() }
    }

    // MARK: - Quest actions

    private func performQuestAction() {
        let shouldReopen = draft?.isComplete ?? false
        guard saveDraft(), let id = selectedID else { return }
        if shouldReopen {
            store.reopen(id)
            showCompleted = false
            SoundPlayer.shared.play(sound: .new)
        } else {
            guard store.turnIn(id) else {
                validationLabel?.stringValue = L10n.text(
                    "complete_all_checklist_objectives_before_turning_in_the_quest")
                return
            }
            showCompleted = true
            SoundPlayer.shared.play(sound: .complete)
        }
        refreshSidebar()
    }

    private func deleteQuest() {
        guard let id = selectedID else { return }
        let alert = NSAlert()
        alert.messageText = L10n.text("abandon_this_quest")
        alert.informativeText = L10n.text("the_quest_and_its_objectives_will_be_removed_from_the_journal")
        alert.addButton(withTitle: L10n.text("abandon_quest"))
        alert.addButton(withTitle: L10n.text("keep"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.isDirty = false
            self.selectedID = nil
            self.draft = nil
            self.store.delete(id)
            SoundPlayer.shared.play(sound: .abandoned)
            let first = self.showCompleted ? self.store.completedQuests.first : self.store.activeQuests.first
            self.selectedID = first?.id
            self.draft = first
            self.refreshSidebar()
            self.renderEditor()
        }
    }

    // MARK: - Overlay settings

    private func showSettings() {
        let menu = NSMenu()
        let reset = NSMenuItem(
            title: L10n.text("reset_overlay_position"), action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())
        for (title, opacity) in [
            (L10n.text("subtle_background_35"), 0.35), (L10n.text("transparent_background_60"), 0.60),
            (L10n.text("dark_background_80"), 0.80), (L10n.text("opaque_background_100"), 1.0)
        ] {
            let item = NSMenuItem(title: title, action: #selector(changeOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = opacity
            // Treat nearby saved values (including the default 0.78) as the same preset.
            item.state = abs(store.settings.opacity - opacity) < 0.03 ? .on : .off
            menu.addItem(item)
        }
        // Place the menu above the footer settings button.
        menu.popUp(positioning: nil, at: NSPoint(x: 295, y: 60), in: window.contentView)
    }

    @objc private func resetPosition() {
        resetOverlay?()
    }
    @objc private func changeOpacity(_ sender: NSMenuItem) {
        guard let opacity = sender.representedObject as? Double else { return }
        store.updateSettings { $0.opacity = opacity }
    }

    func prepareToQuit() -> Bool {
        commitBeforeNavigation()
    }
}
