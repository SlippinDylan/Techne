import Foundation
import Testing
@testable import DevNexus

struct ProcessUtilsTests {
    @Test
    func runAndWaitForTerminationSyncReturnsProcessExitStatus() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exit 7"]

        let status = try ProcessUtils.runAndWaitForTerminationSync(process)

        #expect(status == 7)
    }

    @Test
    func runAndWaitForTerminationSyncThrowsWhenProcessCannotLaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/path/that/does/not/exist")

        do {
            _ = try ProcessUtils.runAndWaitForTerminationSync(process, errorDomain: "ProcessUtilsTests")
            Issue.record("expected runAndWaitForTerminationSync to throw launch error")
        } catch {
            #expect(true)
        }
    }
}
