import Foundation

// The version identifies the on-disk schema, independently of the app version.
struct QuestDocument: Codable {
    static let currentVersion = 1

    var version = currentVersion
    var quests: [Quest] = []
    var focusedQuestID: UUID?
}
