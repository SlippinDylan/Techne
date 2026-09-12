import Foundation
import Testing
@testable import Techne

struct BrowserLaunchRequestTests {
    @Test
    func devServerLaunchCanSkipURLForChromium() {
        let browser = Browser(
            type: .chrome,
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            isDefault: false
        )

        let request = BrowserLaunchRequest.devServer(
            browser: browser,
            port: 5173,
            projectPath: "/Users/test/project",
            shouldOpenURL: false,
            launchSource: "project-card"
        )

        #expect(request.url == nil)
        #expect(request.opensInNewInstance)
        #expect(request.tracksInstance)
        #expect(request.requestedDebugPort == AppConfig.Browser.defaultDebugPort)
        #expect(request.profileDirectoryName == "dev-server-5173")
        #expect(request.launchTarget == BrowserLaunchTarget(
            launchSource: "project-card",
            serverPort: 5173,
            projectPath: "/Users/test/project"
        ))
        #expect(request.launchKey == "project-card:5173:/Users/test/project:com.google.Chrome")
    }

    @Test
    func safariRequestKeepsURLButDisablesChromiumOnlyFeatures() {
        let browser = Browser(
            type: .safari,
            appURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            isDefault: true
        )

        let request = BrowserLaunchRequest.devServer(
            browser: browser,
            port: 3000,
            projectPath: "/Users/test/project",
            shouldOpenURL: true,
            launchSource: "project-card"
        )

        #expect(request.url == "http://localhost:3000")
        #expect(request.opensInNewInstance == false)
        #expect(request.tracksInstance == false)
        #expect(request.requestedDebugPort == nil)
        #expect(request.launchTarget == BrowserLaunchTarget(
            launchSource: "project-card",
            serverPort: 3000,
            projectPath: "/Users/test/project"
        ))
    }

    @Test
    func manualLaunchSupportsBothURLAndStandaloneModes() {
        let browser = Browser(
            type: .chrome,
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            isDefault: false
        )

        let standalone = BrowserLaunchRequest.manual(
            browser: browser,
            url: nil,
            launchSource: "dev-environment-manual"
        )
        let withURL = BrowserLaunchRequest.manual(
            browser: browser,
            url: "localhost:4173",
            launchSource: "dev-environment-manual"
        )

        #expect(standalone.url == nil)
        #expect(standalone.launchTarget == nil)
        #expect(standalone.profileDirectoryName == "manual-browser-instance")
        #expect(standalone.requestedDebugPort == AppConfig.Browser.defaultDebugPort)
        #expect(withURL.normalizedURL == "http://localhost:4173")
        #expect(withURL.launchSource == "dev-environment-manual")
    }
}
