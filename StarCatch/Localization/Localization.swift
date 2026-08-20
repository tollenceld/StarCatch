import Foundation

/// Languages shipped by StarCatch. Selection is owned by iOS; the app never
/// writes an override, so permission prompts and SwiftUI content stay aligned.
enum SupportedLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    init(locale: Locale) {
        let code = locale.language.languageCode?.identifier.lowercased()
        let script = locale.language.script?.identifier.lowercased()
        if code == "zh", script != "hant" {
            self = .simplifiedChinese
        } else {
            self = .english
        }
    }

    static var current: SupportedLanguage {
        if let preferred = Bundle.main.preferredLocalizations.first {
            return SupportedLanguage(locale: Locale(identifier: preferred))
        }
        return SupportedLanguage(locale: .current)
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

/// Lookup for presentation strings assembled outside SwiftUI's localizable
/// initializers. An explicit language is supported for deterministic tests and
/// for compiling both satellite presentations without mutating global state.
enum L10n {
    static func text(
        _ key: String,
        table: String? = nil,
        language: SupportedLanguage = .current
    ) -> String {
        localizedBundle(for: language).localizedString(
            forKey: key,
            value: key,
            table: table
        )
    }

    static func format(
        _ key: String,
        table: String? = nil,
        language: SupportedLanguage = .current,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: text(key, table: table, language: language),
            locale: language.locale,
            arguments: arguments
        )
    }

    private static func localizedBundle(for language: SupportedLanguage) -> Bundle {
        guard let path = Bundle.main.path(
            forResource: language.rawValue,
            ofType: "lproj"
        ), let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
