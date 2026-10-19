import Foundation

public enum AppLanguage: String, CaseIterable, Sendable, Codable, Hashable {
    case en, de, fr, es, ru, uk, it, ja, zh

    /// Locale for SwiftUI's `\.environment(\.locale, …)` override
    public var locale: Locale { Locale(identifier: rawValue) }

    /// The language's own name, for the in-app picker
    public var nativeName: String {
        switch self {
        case .en: return "English"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .es: return "Español"
        case .ru: return "Русский"
        case .uk: return "Українська"
        case .it: return "Italiano"
        case .ja: return "日本語"
        case .zh: return "中文"
        }
    }

    /// Resolves a translation table, falling back to English
    public func pick(_ table: [AppLanguage: String]) -> String {
        table[self] ?? table[.en] ?? ""
    }

    public static func matching(locale: Locale) -> AppLanguage {
        let code = locale.language.languageCode?.identifier ?? "en"
        return AppLanguage(rawValue: code) ?? .en
    }
}
