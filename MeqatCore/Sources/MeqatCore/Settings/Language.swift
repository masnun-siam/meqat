import Foundation

/// The language Meqat shows its text in. Raw values are the `AppleLanguages` codes.
public enum Language: String, CaseIterable, Sendable, Equatable {
    case english = "en"
    case bangla = "bn"

    /// The locale display formatters use. Bangla asks for Bengali digits, since plain `bn` prints Latin ones on macOS.
    public var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_US_POSIX")
        case .bangla: Locale(identifier: "bn@numbers=beng")
        }
    }

    /// Resolves the stored `AppleLanguages` override and the Mac's preferred languages to English or Bangla:
    /// the override when it is non-empty, otherwise the preferred list, taking the first entry that is
    /// English or Bangla, and English when there is none. Pure: reads no `Locale`, `Bundle` or `UserDefaults`.
    public static func resolve(override: [String]?, preferred: [String]) -> Language {
        let candidates = override.flatMap { $0.isEmpty ? nil : $0 } ?? preferred
        return candidates.lazy.compactMap(Language.init(code:)).first ?? .english
    }

    /// The `en` or `bn` language part of a code such as `bn-BD` or `en_US`; nil for any other language.
    init?(code: String) {
        let part = code.prefix { $0 != "-" && $0 != "_" }.lowercased()
        self.init(rawValue: part)
    }

    /// The text for `key` in this language. Keys are the English text, so English returns `key` itself,
    /// and a Bangla lookup with no entry (or no Bangla bundle) falls back to it.
    func localized(_ key: String, table: String) -> String {
        guard self == .bangla, let bundle = Self.banglaBundle else { return key }
        return bundle.localizedString(forKey: key, value: key, table: table)
    }

    // SwiftPM emits no en.lproj for the source language, so only the bn bundle is ever looked up.
    private static let banglaBundle: Bundle? = Bundle.module.path(forResource: "bn", ofType: "lproj").flatMap(Bundle.init(path:))
}

/// What the language picker offers. `system` stores no override, so Meqat follows the Mac.
public enum LanguageChoice: CaseIterable, Sendable, Equatable {
    case system, english, bangla

    /// The choice for a stored `AppleLanguages` override; an override other than `en` or `bn`
    /// shows as the language it resolves to.
    public init(override: [String]?) {
        guard let override, !override.isEmpty else {
            self = .system
            return
        }
        self = Language.resolve(override: override, preferred: []) == .bangla ? .bangla : .english
    }

    /// The `AppleLanguages` value to store; nil removes the override.
    public var override: [String]? {
        switch self {
        case .system: nil
        case .english: [Language.english.rawValue]
        case .bangla: [Language.bangla.rawValue]
        }
    }
}
