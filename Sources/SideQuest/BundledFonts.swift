import AppKit
import CoreText

@MainActor
enum BundledFonts {
    static let regularName = "CinzelDecorative-Regular"
    static let boldName = "CinzelDecorative-Bold"
    static let metamorphousName = "Metamorphous-Regular"
    static let metamorphousPostScriptName = "Metamorphous"

    static func register() {
        let resources = resourceBundle

        for name in [regularName, boldName, metamorphousName] {
            register(name, in: resources)
        }
    }

    // The packaged app embeds the SwiftPM resource bundle; command-line builds
    // resolve it through Bundle.module instead.
    private static var resourceBundle: Bundle {
        if let url = Bundle.main.url(forResource: "SideQuest_SideQuest", withExtension: "bundle"),
            let bundle = Bundle(url: url)
        {
            return bundle
        } else {
            return Bundle.module
        }
    }

    private static func register(_ name: String, in resources: Bundle) {
        guard let url = resources.url(forResource: name, withExtension: "ttf", subdirectory: "fonts") else {
            NSLog(L10n.text("missing_font_in_app_resources_value"), name)
            return
        }
        var registrationError: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError),
            let error = registrationError?.takeRetainedValue(),
            CFErrorGetCode(error) != CTFontManagerError.alreadyRegistered.rawValue
        {
            NSLog(L10n.text("failed_to_register_font_value_value"), name, String(describing: error))
        }
    }
}
