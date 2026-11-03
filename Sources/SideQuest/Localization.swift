import Foundation

/// Bundle resolves the user's preferred supported language (including regional variants).
/// Keep the SwiftPM resource bundle explicit: Bundle.main contains the executable, not these tables.
enum L10n {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = Bundle.module.localizedString(forKey: key, value: nil, table: "Localizable")
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
