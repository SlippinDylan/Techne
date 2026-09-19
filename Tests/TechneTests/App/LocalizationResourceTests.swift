import Foundation
import Testing
@testable import Techne

struct LocalizationResourceTests {
    @Test
    func appBundleUsesEnglishFallbackAndDeclaresSupportedLanguages() {
        #expect(Bundle.main.developmentLocalization == "en")
        #expect(Set(Bundle.main.localizations).isSuperset(of: ["en", "zh-Hans", "zh-Hant"]))
    }

    @Test(arguments: ["en", "zh-Hans", "zh-Hant"])
    func appBundleContainsLocalizedUIAndPermissionResources(language: String) throws {
        let localizablePath = try #require(
            Bundle.main.path(
                forResource: "Localizable",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: language
            )
        )
        let infoPlistPath = try #require(
            Bundle.main.path(
                forResource: "InfoPlist",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: language
            )
        )

        #expect(FileManager.default.fileExists(atPath: localizablePath))
        #expect(FileManager.default.fileExists(atPath: infoPlistPath))
    }

    @Test
    func persistedProjectTypeRawValuesRemainCompatible() {
        #expect(ProjectType.devServer.rawValue == "开发服务与实例")
        #expect(ProjectType.miniApp.rawValue == "微信小程序构建")
    }
}
