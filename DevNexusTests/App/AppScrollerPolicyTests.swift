import AppKit
import Testing
@testable import DevNexus

struct AppScrollerPolicyTests {
    @Test
    func mainContentFollowsLegacySystemPreference() {
        let configuration = AppScrollerPolicy.configuration(
            for: .mainContent,
            preferredStyle: .legacy
        )

        #expect(configuration.scrollerStyle == .legacy)
        #expect(configuration.autohidesScrollers == false)
        #expect(configuration.controlSize == .regular)
    }

    @Test
    func utilityPanelUsesOverlayAutohideWhenSystemPrefersOverlay() {
        let configuration = AppScrollerPolicy.configuration(
            for: .utilityPanel,
            preferredStyle: .overlay
        )

        #expect(configuration.scrollerStyle == .overlay)
        #expect(configuration.autohidesScrollers)
        #expect(configuration.controlSize == .small)
    }

    @Test
    func utilityPanelKeepsLegacyVisibilityWhenSystemWantsVisibleScrollBars() {
        let configuration = AppScrollerPolicy.configuration(
            for: .utilityPanel,
            preferredStyle: .legacy
        )

        #expect(configuration.scrollerStyle == .legacy)
        #expect(configuration.autohidesScrollers == false)
        #expect(configuration.controlSize == .small)
    }
}
