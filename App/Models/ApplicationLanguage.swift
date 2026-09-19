//
//  ApplicationLanguage.swift
//  Techne
//

import Foundation

enum ApplicationLanguage: String, CaseIterable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    static let preferenceKey = "application.language"
    static let appleLanguagesKey = "AppleLanguages"

    var displayName: String {
        switch self {
        case .system:
            AppLocalized("跟随系统")
        case .english:
            "English"
        case .simplifiedChinese:
            "简体中文"
        case .traditionalChinese:
            "繁體中文"
        }
    }

    static func selected(in defaults: UserDefaults = .standard) -> Self {
        guard let rawValue = defaults.string(forKey: preferenceKey),
              let language = Self(rawValue: rawValue) else {
            return .system
        }

        return language
    }

    /// Returns whether the preference changed and a relaunch is needed.
    @discardableResult
    static func select(_ language: Self, in defaults: UserDefaults = .standard) -> Bool {
        guard selected(in: defaults) != language else {
            return false
        }

        defaults.set(language.rawValue, forKey: preferenceKey)

        switch language {
        case .system:
            defaults.removeObject(forKey: appleLanguagesKey)
        case .english, .simplifiedChinese, .traditionalChinese:
            defaults.set([language.rawValue], forKey: appleLanguagesKey)
        }

        return true
    }
}
