import AppKit
import Testing
@testable import DevNexus

struct AppScrollerPolicyTests {
    @Test
    func mainContentUsesUnifiedOverlayScrollerChromeEvenWhenSystemPrefersLegacy() {
        let configuration = AppScrollerPolicy.configuration(
            for: .mainContent,
            preferredStyle: .legacy
        )

        #expect(configuration.scrollerStyle == .overlay)
        #expect(configuration.autohidesScrollers)
        #expect(configuration.controlSize == .regular)
    }

    @Test
    func utilityPanelUsesSameUnifiedScrollerChromeAsMainContent() {
        let configuration = AppScrollerPolicy.configuration(
            for: .utilityPanel,
            preferredStyle: .overlay
        )

        #expect(configuration.scrollerStyle == .overlay)
        #expect(configuration.autohidesScrollers)
        #expect(configuration.controlSize == .regular)
    }

    @Test
    func consoleViewportPrefersOverlayAutohideAndRegularWidthEvenWhenSystemPrefersLegacy() {
        let configuration = AppScrollerPolicy.configuration(
            for: .consoleViewport,
            preferredStyle: .legacy
        )

        #expect(configuration.scrollerStyle == .overlay)
        #expect(configuration.autohidesScrollers)
        #expect(configuration.controlSize == .regular)
    }
}
