import Foundation
import Testing
@testable import DevNexus

struct BrowserLaunchPlanTests {
    @Test
    func chromiumPlanOmitsURLWhenLaunchingStandaloneInstance() throws {
        let browser = Browser(
            type: .chrome,
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            isDefault: false
        )
        let request = BrowserLaunchRequest.devServer(
            browser: browser,
            port: 4173,
            projectPath: "/Users/test/project",
            shouldOpenURL: false,
            launchSource: "discovered-server"
        )

        let profileDirectoryURL = URL(fileURLWithPath: "/tmp/devnexus-tests/profile-1")
        let plan = try BrowserLaunchPlan(
            request: request,
            profileDirectoryURL: profileDirectoryURL,
            resolvedDebugPort: 9333
        )

        #expect(plan.applicationURL == browser.appURL)
        #expect(plan.arguments.contains("--user-data-dir=\(profileDirectoryURL.path)"))
        #expect(plan.arguments.contains("--remote-debugging-port=9333"))
        #expect(plan.arguments.contains("--no-first-run"))
        #expect(plan.arguments.contains("--no-default-browser-check"))
        #expect(plan.arguments.contains("http://localhost:4173") == false)
        #expect(plan.urlsToOpen.isEmpty)
        #expect(plan.createsNewApplicationInstance)
        #expect(plan.activates)
    }

    @Test
    func safariPlanUsesURLPayloadWithoutChromiumFlags() throws {
        let browser = Browser(
            type: .safari,
            appURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            isDefault: false
        )
        let request = BrowserLaunchRequest.devServer(
            browser: browser,
            port: 3000,
            projectPath: "/Users/test/project",
            shouldOpenURL: true,
            launchSource: "project-card"
        )

        let plan = try BrowserLaunchPlan(
            request: request,
            profileDirectoryURL: nil,
            resolvedDebugPort: nil
        )

        #expect(plan.applicationURL == browser.appURL)
        #expect(plan.arguments.isEmpty)
        #expect(plan.urlsToOpen.map(\.absoluteString) == ["http://localhost:3000"])
        #expect(plan.createsNewApplicationInstance == false)
    }
}
