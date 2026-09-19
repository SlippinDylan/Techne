import Foundation
import Testing
@testable import Techne

struct ApplicationLanguageTests {
    @Test
    func defaultsToFollowingTheSystem() {
        let (defaults, suiteName) = makeDefaults()
        defer { removeDefaults(suiteName) }

        #expect(ApplicationLanguage.selected(in: defaults) == .system)
    }

    @Test(arguments: [
        (ApplicationLanguage.english, "en"),
        (.simplifiedChinese, "zh-Hans"),
        (.traditionalChinese, "zh-Hant")
    ])
    func selectingAnExplicitLanguageStoresThePreferenceAndAppLanguageOverride(
        language: ApplicationLanguage,
        expectedAppleLanguage: String
    ) {
        let (defaults, suiteName) = makeDefaults()
        defer { removeDefaults(suiteName) }

        #expect(ApplicationLanguage.select(language, in: defaults))
        #expect(ApplicationLanguage.selected(in: defaults) == language)
        #expect(defaults.stringArray(forKey: ApplicationLanguage.appleLanguagesKey) == [expectedAppleLanguage])
    }

    @Test
    func selectingSystemRemovesTheAppLanguageOverride() {
        let (defaults, suiteName) = makeDefaults()
        defer { removeDefaults(suiteName) }
        defaults.set(ApplicationLanguage.english.rawValue, forKey: ApplicationLanguage.preferenceKey)
        defaults.set([ApplicationLanguage.english.rawValue], forKey: ApplicationLanguage.appleLanguagesKey)

        #expect(ApplicationLanguage.select(.system, in: defaults))
        #expect(ApplicationLanguage.selected(in: defaults) == .system)
        #expect(
            defaults.persistentDomain(forName: suiteName)?[ApplicationLanguage.appleLanguagesKey] == nil
        )
    }

    @Test
    func selectingTheCurrentLanguageDoesNotRequestAnotherRelaunch() {
        let (defaults, suiteName) = makeDefaults()
        defer { removeDefaults(suiteName) }
        defaults.set(ApplicationLanguage.english.rawValue, forKey: ApplicationLanguage.preferenceKey)

        #expect(ApplicationLanguage.select(.english, in: defaults) == false)
    }

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "ApplicationLanguageTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func removeDefaults(_ suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
}
