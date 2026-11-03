import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Main persistence
    private var store: QuestStore!

    // Controllers
    private var overlay: OverlayController!
    private var journal: JournalController!

    // In-app menus
    private var visibilityItem: NSMenuItem!
    private var collapseItem: NSMenuItem!

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        BundledFonts.register()

        setUpStore()
        setUpControllers()

        buildMainMenu()

        _ = store.observe { [weak self] in self?.refreshStatusMenu() }

        journal.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        journal.prepareToQuit() ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        journal.show()
        return true
    }

    // MARK: - Startup

    private func setUpStore() {
        let isDemo = CommandLine.arguments.contains("--demo")
        let questsFileURL: URL?
        let settingsFileURL: URL?

        // Demo mode is memory-only. A custom quest file gets its own settings
        // sibling so it cannot change the normal desktop overlay preferences.
        if isDemo {
            (questsFileURL, settingsFileURL) = (nil, nil)
        } else if let index = CommandLine.arguments.firstIndex(of: "--data-file"),
            CommandLine.arguments.count > index + 1
        {
            let customURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            questsFileURL = customURL
            settingsFileURL = customURL.deletingPathExtension().appendingPathExtension("settings.json")
        } else {
            (questsFileURL, settingsFileURL) = (QuestStore.defaultFileURL, QuestStore.defaultSettingsFileURL)
        }

        store = QuestStore(fileURL: questsFileURL, settingsFileURL: settingsFileURL, demo: isDemo)
    }

    private func setUpControllers() {
        journal = JournalController(store: store)

        overlay = OverlayController(store: store)
        overlay.openJournal = { [weak self] in self?.journal.show() }
        overlay.openQuestJournal = { [weak self] id in self?.journal.showQuest(id) }

        journal.toggleOverlay = { [weak self] in self?.overlay.toggleVisibility() }
        journal.resetOverlay = { [weak self] in self?.overlay.resetPosition() }
    }

    // MARK: - Main menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        buildMainMenuSection(mainMenu: mainMenu)

        buildQuestMenuSection(mainMenu: mainMenu)

        buildEditMenuSection(mainMenu: mainMenu)

        NSApp.mainMenu = mainMenu
    }

    private func buildMainMenuSection(mainMenu: NSMenu) {
        let appMenu = NSMenu()
        let appItem = NSMenuItem()

        appMenu.addItem(
            NSMenuItem(title: L10n.text("about_side_quest"), action: #selector(showAbout), keyEquivalent: ""))
        appMenu.items.last?.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(
                title: L10n.text("hide_side_quest"), action: #selector(NSApplication.hide(_:)),
                keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(
                title: L10n.text("close_journal"), action: #selector(NSWindow.performClose(_:)),
                keyEquivalent: "w"))
        appMenu.addItem(
            NSMenuItem(
                title: L10n.text("quit_side_quest"), action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))
        appItem.submenu = appMenu

        mainMenu.addItem(appItem)
    }

    private func buildQuestMenuSection(mainMenu: NSMenu) {
        let fileItem = NSMenuItem()
        let file = NSMenu(title: L10n.text("quest"))

        fileItem.title = L10n.text("quest")
        file.addItem(menuItem(L10n.text("new_quest"), action: #selector(newQuest), key: "n"))
        file.addItem(menuItem(L10n.text("open_journal"), action: #selector(openJournal), key: "j"))
        fileItem.submenu = file

        mainMenu.addItem(fileItem)
    }

    private func buildEditMenuSection(mainMenu: NSMenu) {
        let editItem = NSMenuItem()
        editItem.title = L10n.text("edit")

        let edit = NSMenu(title: L10n.text("edit"))
        edit.addItem(NSMenuItem(title: L10n.text("undo"), action: Selector(("undo:")), keyEquivalent: "z"))

        let redo = NSMenuItem(title: L10n.text("redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]

        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(
            NSMenuItem(title: L10n.text("cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(
            NSMenuItem(title: L10n.text("copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(
            NSMenuItem(title: L10n.text("paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(
            NSMenuItem(
                title: L10n.text("select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit

        mainMenu.addItem(editItem)
    }

    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func refreshStatusMenu() {
        visibilityItem?.title =
            store.settings.isVisible ? L10n.text("hide_overlay") : L10n.text("show_overlay")
        collapseItem?.title =
            store.settings.isCollapsed ? L10n.text("expand_tracker") : L10n.text("collapse_tracker")
    }

    // MARK: - Menu actions

    @objc
    private func openJournal() {
        journal.show()
    }

    @objc
    private func newQuest() {
        journal.createQuest()
    }

    @objc
    private func toggleVisibility() {
        overlay.toggleVisibility()
    }

    @objc
    private func toggleCollapsed() {
        store.updateSettings { $0.isCollapsed.toggle() }
    }

    @objc
    private func resetPosition() {
        overlay.resetPosition()
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }

    @objc
    private func showAbout() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Side Quest",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            .credits: NSAttributedString(
                string: L10n.text("about_description"), attributes: [.paragraphStyle: paragraphStyle])
        ])
    }
}
