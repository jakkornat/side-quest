import Foundation

@MainActor
final class QuestStore {
    private(set) var document: QuestDocument
    private let fileURL: URL?
    private let settingsFileURL: URL?
    private var settingsDocument = SettingsDocument()
    private var observers: [UUID: () -> Void] = [:]
    private var questPersistenceError: String?
    private var settingsPersistenceError: String?
    // A failed read disables writes so a corrupt or newer file remains recoverable.
    private var canPersistQuests = true
    private var canPersistSettings = true

    init(fileURL: URL?, settingsFileURL: URL?, demo: Bool = false) {
        self.fileURL = fileURL
        self.settingsFileURL = settingsFileURL
        document = QuestDocument(quests: demo ? Quest.examples : [])
        loadQuests()
        loadSettings()
    }

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SideQuest", isDirectory: true)
            .appendingPathComponent("quests.json")
    }

    static var defaultSettingsFileURL: URL {
        defaultFileURL.deletingLastPathComponent().appendingPathComponent("settings.json")
    }

    var persistenceError: String? {
        let errors = [questPersistenceError, settingsPersistenceError].compactMap { $0 }
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    var quests: [Quest] { document.quests }
    var activeQuests: [Quest] { sorted(document.quests.filter { !$0.isComplete }) }
    var completedQuests: [Quest] {
        document.quests.filter(\.isComplete).sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
    }
    var settings: OverlaySettings { settingsDocument.overlay }
    var focusedQuestID: UUID? { document.focusedQuestID }

    // MARK: - Quest ordering

    private func sorted(_ quests: [Quest]) -> [Quest] {
        // Break priority ties by creation time, then UUID, so refreshes do not
        // reshuffle quests that otherwise compare equally.
        quests.sorted {
            if $0.priority != $1.priority { return Priority.isHigher($0.priority, than: $1.priority) }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    // MARK: - Observation

    @discardableResult
    func observe(_ callback: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = callback
        return id
    }

    // MARK: - Quest changes

    @discardableResult
    func save(_ input: Quest) -> Bool {
        var quest = input
        quest.title = quest.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quest.title.isEmpty, let priority = Priority.normalize(quest.priority) else { return false }
        quest.priority = priority
        quest.objectives = quest.objectives.compactMap {
            var objective = $0
            objective.title = objective.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return objective.title.isEmpty ? nil : objective
        }
        quest.invalidateTurnInIfNeeded()
        if let index = document.quests.firstIndex(where: { $0.id == quest.id }) {
            document.quests[index] = quest
        } else {
            document.quests.append(quest)
        }
        changed()
        return true
    }

    func toggleObjective(questID: UUID, objectiveID: UUID) {
        guard let questIndex = document.quests.firstIndex(where: { $0.id == questID }),
            let objectiveIndex = document.quests[questIndex].objectives.firstIndex(where: {
                $0.id == objectiveID
            })
        else { return }
        document.quests[questIndex].objectives[objectiveIndex].isComplete.toggle()
        document.quests[questIndex].invalidateTurnInIfNeeded()
        changed()
    }

    @discardableResult
    func turnIn(_ id: UUID) -> Bool {
        guard let index = document.quests.firstIndex(where: { $0.id == id }),
            document.quests[index].canTurnIn
        else { return false }
        document.quests[index].completedAt = Date()
        changed()
        return true
    }

    func reopen(_ id: UUID) {
        guard let index = document.quests.firstIndex(where: { $0.id == id }),
            document.quests[index].isComplete
        else { return }
        document.quests[index].completedAt = nil
        if !document.quests[index].objectives.isEmpty {
            // Reopen from the last step and retain earlier progress.
            let last = document.quests[index].objectives.count - 1
            document.quests[index].objectives[last].isComplete = false
        }
        changed()
    }

    func toggleExpanded(_ id: UUID) {
        guard let index = document.quests.firstIndex(where: { $0.id == id }) else { return }
        document.quests[index].isExpanded.toggle()
        changed()
    }

    func toggleFocus(_ id: UUID) {
        guard document.quests.contains(where: { $0.id == id && !$0.isComplete }) else { return }
        document.focusedQuestID = document.focusedQuestID == id ? nil : id
        changed()
    }

    func delete(_ id: UUID) {
        document.quests.removeAll { $0.id == id }
        changed()
    }

    // MARK: - Overlay settings

    func updateSettings(_ update: (inout OverlaySettings) -> Void, notify: Bool = true) {
        update(&settingsDocument.overlay)
        persistSettings()
        if notify { notifyObservers() }
    }

    // MARK: - Change notifications

    private func changed() {
        if let focusedID = document.focusedQuestID,
            !document.quests.contains(where: { $0.id == focusedID && !$0.isComplete })
        {
            document.focusedQuestID = nil
        }
        persist()
        notifyObservers()
    }

    private func notifyObservers() {
        // Call a snapshot: a callback may register another observer.
        for observer in Array(observers.values) { observer() }
    }

    // MARK: - Persistence

    private func loadQuests() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            document = try JSONDecoder().decode(QuestDocument.self, from: Data(contentsOf: fileURL))
            // Unknown schemas must never be overwritten with this version's model.
            guard document.version == QuestDocument.currentVersion else {
                canPersistQuests = false
                questPersistenceError = L10n.text(
                    "this_file_was_created_by_a_newer_version_of_the_app_it_will_not_be_overwritten")
                return
            }
        } catch {
            canPersistQuests = false
            questPersistenceError = L10n.text(
                "could_not_read_quests_the_original_file_remains_unchanged_value",
                error.localizedDescription)
        }
    }

    private func loadSettings() {
        guard let settingsFileURL, FileManager.default.fileExists(atPath: settingsFileURL.path) else {
            return
        }
        do {
            settingsDocument = try JSONDecoder().decode(
                SettingsDocument.self, from: Data(contentsOf: settingsFileURL))
            guard settingsDocument.version == SettingsDocument.currentVersion else {
                canPersistSettings = false
                settingsPersistenceError = L10n.text("settings_newer_version")
                return
            }
        } catch {
            canPersistSettings = false
            settingsPersistenceError = L10n.text("could_not_read_settings", error.localizedDescription)
        }
    }

    private func persist() {
        guard let fileURL, canPersistQuests else { return }
        questPersistenceError = write(document, to: fileURL, failureKey: "could_not_save_quests_value")
    }

    private func persistSettings() {
        guard let settingsFileURL, canPersistSettings else { return }
        settingsPersistenceError = write(
            settingsDocument, to: settingsFileURL, failureKey: "could_not_save_settings")
    }

    private func write<T: Encodable>(_ value: T, to url: URL, failureKey: String) -> String? {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            // Atomic replacement leaves the previous file intact if writing fails.
            try encoder.encode(value).write(to: url, options: .atomic)
            return nil
        } catch {
            return L10n.text(failureKey, error.localizedDescription)
        }
    }
}
