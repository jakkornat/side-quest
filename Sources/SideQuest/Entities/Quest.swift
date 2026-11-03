import Foundation

enum Severity: Int, Codable, CaseIterable, Sendable {
    case trivial, normal, important, urgent, critical

    var title: String {
        switch self {
        case .trivial: L10n.text("severity_trivial")
        case .normal: L10n.text("severity_normal")
        case .important: L10n.text("severity_important")
        case .urgent: L10n.text("severity_urgent")
        case .critical: L10n.text("severity_critical")
        }
    }
}

struct Objective: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var isComplete = false
}

enum QuestProgress {
    case notStarted, inProgress, readyToTurnIn

    var icon: String {
        switch self {
        case .notStarted: "﹖"
        case .inProgress: "···"
        case .readyToTurnIn: "!"
        }
    }

    var title: String {
        switch self {
        case .notStarted: L10n.text("not_started")
        case .inProgress: L10n.text("in_progress")
        case .readyToTurnIn: L10n.text("ready_to_turn_in")
        }
    }
}

struct Quest: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var priority = "1"
    var severity: Severity = .important
    var objectives: [Objective] = []
    var createdAt = Date()
    var completedAt: Date?
    var isExpanded = true

    var isComplete: Bool { completedAt != nil }
    var displayPriority: String {
        // Keep unusually long priorities from consuming the entire quest heading.
        // Ten digits plus an ellipsis leave room for the surrounding brackets.
        priority.count > 12 ? String(priority.prefix(10)) + "…" : priority
    }
    var currentObjective: Objective? { objectives.first(where: { !$0.isComplete }) }
    var completedCount: Int { objectives.filter(\.isComplete).count }
    var hasCompletedAllObjectives: Bool {
        !objectives.isEmpty
            && objectives.allSatisfy {
                $0.isComplete && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }
    var canTurnIn: Bool { !isComplete && hasCompletedAllObjectives }
    var progress: QuestProgress {
        if hasCompletedAllObjectives { return .readyToTurnIn }
        return completedCount > 0 ? .inProgress : .notStarted
    }

    mutating func invalidateTurnInIfNeeded() {
        // Checking the final objective never turns in a quest. Editing an already
        // turned-in quest to leave unfinished objectives makes it active again.
        if !hasCompletedAllObjectives { completedAt = nil }
    }
}

// MARK: - Demo quests

extension Quest {
    static let examples: [Quest] = [
        Quest(
            title: L10n.text("release_your_app"), priority: "100", severity: .urgent,
            objectives: [
                Objective(title: L10n.text("prepare_the_first_prototype"), isComplete: true),
                Objective(title: L10n.text("polish_the_quest_journal")),
                Objective(title: L10n.text("test_the_desktop_overlay")),
                Objective(title: L10n.text("celebrate_the_release"))
            ]),
        Quest(
            title: L10n.text("set_out_to_learn_something_new"), priority: "42", severity: .important,
            objectives: [
                Objective(title: L10n.text("read_one_chapter")),
                Objective(title: L10n.text("write_down_three_key_ideas"))
            ]),
        Quest(
            title: L10n.text("time_away_from_the_screen"), priority: "7", severity: .normal,
            objectives: [
                Objective(title: L10n.text("go_for_a_twenty_minute_walk"))
            ])
    ]
}
