import Foundation

/// Foundation chooses from the app's supported languages using macOS preferences,
/// including a per-app language override. No language is persisted by Narly.
public enum L10n {
    static let bundle: Bundle = Bundle.main.object(forInfoDictionaryKey: "NarlyBuildChannel") != nil
        ? .main : .module

    public static func text(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
