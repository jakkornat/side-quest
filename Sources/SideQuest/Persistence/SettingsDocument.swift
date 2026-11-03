import Foundation

struct OverlaySettings: Codable, Equatable {
    var isCollapsed = false
    var isVisible = true
    var originX: Double?
    var originY: Double?
    var opacity = 0.78
}

struct SettingsDocument: Codable {
    static let currentVersion = 1

    var version = currentVersion
    var overlay = OverlaySettings()
}
