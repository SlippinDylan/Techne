import Foundation
import Testing
@testable import DevNexus

struct ProcessServiceProjectScopeTests {
    @Test
    func descendantWorkingDirectoryMatchesManagedProjectRoot() {
        let process = ProjectProcessSnapshot(
            pid: 99767,
            processGroupID: 99365,
            commandLine: "next-server (v15.5.18)",
            currentWorkingDirectory: "/Users/test/Portlens/app"
        )

        #expect(
            ProjectRootProcessMatcher.matches(
                process: process,
                projectRootPath: "/Users/test/Portlens"
            )
        )
    }

    @Test
    func commandLineContainingProjectRootMatchesWhenWorkingDirectoryIsUnavailable() {
        let process = ProjectProcessSnapshot(
            pid: 99752,
            processGroupID: 99365,
            commandLine: "node /Users/test/Portlens/scripts/workspace-next.mjs dev mock",
            currentWorkingDirectory: nil
        )

        #expect(
            ProjectRootProcessMatcher.matches(
                process: process,
                projectRootPath: "/Users/test/Portlens"
            )
        )
    }

    @Test
    func siblingPathsDoNotMatchManagedProjectRoot() {
        let process = ProjectProcessSnapshot(
            pid: 2201,
            processGroupID: 2201,
            commandLine: "node /Users/test/Portlens-docs/scripts/dev.mjs",
            currentWorkingDirectory: "/Users/test/Portlens-docs/app"
        )

        #expect(
            ProjectRootProcessMatcher.matches(
                process: process,
                projectRootPath: "/Users/test/Portlens"
            ) == false
        )
    }

    @Test
    func stopPlanDeduplicatesMatchedProcessGroupsAndIgnoresUnrelatedStoredPID() {
        let plan = ProjectRootProcessMatcher.stopPlan(
            forProjectRootPath: "/Users/test/Portlens",
            processes: [
                ProjectProcessSnapshot(
                    pid: 111,
                    processGroupID: 111,
                    commandLine: "node /tmp/other-project/dev.mjs",
                    currentWorkingDirectory: "/tmp/other-project"
                ),
                ProjectProcessSnapshot(
                    pid: 99751,
                    processGroupID: 99365,
                    commandLine: "node ./scripts/workspace-next.mjs dev mock",
                    currentWorkingDirectory: "/Users/test/Portlens"
                ),
                ProjectProcessSnapshot(
                    pid: 99752,
                    processGroupID: 99365,
                    commandLine: "node /Users/test/Portlens/app/node_modules/next/dist/bin/next dev",
                    currentWorkingDirectory: "/Users/test/Portlens/app"
                ),
                ProjectProcessSnapshot(
                    pid: 99767,
                    processGroupID: 99365,
                    commandLine: "next-server (v15.5.18)",
                    currentWorkingDirectory: "/Users/test/Portlens/app"
                )
            ]
        )

        #expect(plan.processGroupIDs == [99365])
        #expect(plan.fallbackProcessIDs.isEmpty)
        #expect(plan.matchedPIDs == [99751, 99752, 99767])
    }

    @Test
    func stopPlanDoesNotFallbackToStoredPIDWhenNoProjectScopedProcessMatches() {
        let plan = ProjectRootProcessMatcher.stopPlan(
            forProjectRootPath: "/Users/test/Portlens",
            processes: [
                ProjectProcessSnapshot(
                    pid: 111,
                    processGroupID: 111,
                    commandLine: "node /tmp/other-project/dev.mjs",
                    currentWorkingDirectory: "/tmp/other-project"
                )
            ]
        )

        #expect(plan.processGroupIDs.isEmpty)
        #expect(plan.fallbackProcessIDs.isEmpty)
        #expect(plan.matchedPIDs.isEmpty)
    }

    @Test
    func processListCommandUsesWidePsArguments() {
        let task = SystemProcessInspector.makeProcessListTask()

        #expect(task.executableURL?.path == "/bin/ps")
        #expect(task.arguments == ["-axww", "-o", "pid=,pgid=,command="])
    }

    @Test
    func commandLineLookupUsesWidePsArguments() {
        let task = SystemProcessInspector.makeCommandLineTask(pid: 1234)

        #expect(task.executableURL?.path == "/bin/ps")
        #expect(task.arguments == ["-p", "1234", "-ww", "-o", "command="])
    }

    @Test
    func parseProcessSnapshotsPreservesWidePsCommandLineOutput() {
        let output = """
        99751 99365 node /Users/test/Portlens/app/node_modules/next/dist/bin/next dev --hostname 0.0.0.0 --port 3000
        99767 99365 next-server (v15.5.18)
        """

        let snapshots = SystemProcessInspector.parseProcessSnapshots(
            from: output,
            currentWorkingDirectories: [
                99751: "/Users/test/Portlens/app",
                99767: "/Users/test/Portlens/app"
            ]
        )

        #expect(
            snapshots == [
                ProjectProcessSnapshot(
                    pid: 99751,
                    processGroupID: 99365,
                    commandLine: "node /Users/test/Portlens/app/node_modules/next/dist/bin/next dev --hostname 0.0.0.0 --port 3000",
                    currentWorkingDirectory: "/Users/test/Portlens/app"
                ),
                ProjectProcessSnapshot(
                    pid: 99767,
                    processGroupID: 99365,
                    commandLine: "next-server (v15.5.18)",
                    currentWorkingDirectory: "/Users/test/Portlens/app"
                )
            ]
        )
    }

    @Test
    func listeningTcpTasksAreConstructedBySystemInspector() {
        let scanTask = SystemProcessInspector.makeListeningTCPTask()
        let portTask = SystemProcessInspector.makeListeningPortTask(port: 3000)

        #expect(scanTask?.arguments == ["-iTCP", "-sTCP:LISTEN", "-n", "-P"])
        #expect(portTask?.arguments == ["-i", ":3000", "-sTCP:LISTEN"])
    }
}
