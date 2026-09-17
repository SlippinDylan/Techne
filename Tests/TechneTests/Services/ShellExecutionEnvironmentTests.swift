import Foundation
import Testing
@testable import Techne

struct ShellExecutionEnvironmentTests {
    @Test
    func usesConfiguredSupportedExecutableShell() {
        let shellURL = ShellExecutionEnvironment.shellURL(environment: ["SHELL": "/bin/bash"])

        #expect(shellURL.path == "/bin/bash")
    }

    @Test
    func fallsBackToZshForUnsupportedShell() {
        let shellURL = ShellExecutionEnvironment.shellURL(environment: ["SHELL": "/bin/sh"])

        #expect(shellURL.path == "/bin/zsh")
    }

    @Test
    func usesInteractiveLoginArguments() {
        #expect(ShellExecutionEnvironment.arguments(for: "pnpm dev") == ["-l", "-i", "-c", "pnpm dev"])
    }
}
