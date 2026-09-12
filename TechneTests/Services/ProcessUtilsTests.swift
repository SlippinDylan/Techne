import Foundation
import Testing
@testable import Techne

struct ProcessUtilsTests {
    @Test
    func runAndCaptureCollectsStandardOutputAndStandardError() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf 'out'; printf 'err' 1>&2; exit 3"]

        let result = try await ProcessUtils.runAndCapture(process)

        #expect(result.terminationStatus == 3)
        #expect(String(data: result.standardOutput, encoding: .utf8) == "out")
        #expect(String(data: result.standardError, encoding: .utf8) == "err")
    }

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
