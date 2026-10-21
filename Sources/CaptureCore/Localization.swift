import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system, english = "en", chinese = "zh-Hans", japanese = "ja"

    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        // Choose the first supported language in the user's ordered preferences.
        for identifier in preferredLanguages {
            let prefix = identifier.lowercased().split(separator: "-").first
            if prefix == "en" { return .english }
            if prefix == "zh" { return .chinese }
            if prefix == "ja" { return .japanese }
        }
        return .english
    }
    public var locale: Locale { Locale(identifier: resolved().rawValue) }
    public var nativeName: String {
        switch self { case .system: "跟随系统"; case .english: "English"; case .chinese: "简体中文"; case .japanese: "日本語" }
    }
    public var promptName: String {
        switch resolved() { case .chinese: "Simplified Chinese"; case .japanese: "Japanese"; default: "English" }
    }
}

/// Foundation messages share the native UI's explicit language preference.
/// Static SwiftUI labels are resolved by the locale environment at display time.
public enum L10n {
    private static let lock = NSLock()
    private static var selection: AppLanguage = .system
    public static var language: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return selection }
        set { lock.lock(); defer { lock.unlock() }; selection = newValue }
    }
    public static let resources: Bundle = {
        if Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en") != nil {
            return Bundle.main
        }
        return Bundle.module
    }()
    public static func text(_ key: String, language: AppLanguage? = nil) -> String {
        let code = (language ?? self.language).resolved().rawValue
        guard let path = resources.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: language.locale, arguments: arguments)
    }
}
