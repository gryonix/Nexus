import SwiftUI
import ServiceCatalog

enum ContentLanguageSetting {
    /// The language of generated content — tracks the app/device language
    static var current: AppLanguage {
        AppLanguage.matching(locale: Locale.current)
    }
}

enum UIL10n {
    static func string(_ key: String, _ args: CVarArg...) -> String {
        let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        return args.isEmpty ? format : String(format: format, arguments: args)
    }
}
