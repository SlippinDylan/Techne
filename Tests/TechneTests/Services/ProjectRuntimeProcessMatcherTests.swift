import Testing
@testable import Techne

struct ProjectRuntimeProcessMatcherTests {
    @Test
    func recoversShellProjectFromMatchingCommandAndWorkingDirectory() {
        let project = Project(
            name: "staff-miniapp",
            path: "/Users/test/staff-miniapp",
            type: .miniApp,
            startCommand: "pnpm dev:weapp"
        )
        let snapshots = [
            ProjectProcessSnapshot(
                pid: 7911,
                processGroupID: 7911,
                commandLine: "node /opt/pnpm dev:weapp",
                currentWorkingDirectory: "/Users/test/staff-miniapp"
            ),
            ProjectProcessSnapshot(
                pid: 9132,
                processGroupID: 7911,
                commandLine: "node ./node_modules/@tarojs/cli/bin/taro build --watch",
                currentWorkingDirectory: "/Users/test/staff-miniapp"
            )
        ]

        let match = ProjectRuntimeProcessMatcher.matches(for: project, in: snapshots)

        #expect(match == ProjectRuntimeProcessMatch(
            representativePID: 7911,
            processGroupIDs: [7911]
        ))
    }

    @Test
    func ignoresResidualWatcherWithoutTheSelectedStartCommand() {
        let project = Project(
            name: "staff-miniapp",
            path: "/Users/test/staff-miniapp",
            type: .miniApp,
            startCommand: "pnpm dev:weapp"
        )
        let snapshots = [
            ProjectProcessSnapshot(
                pid: 25517,
                processGroupID: 24795,
                commandLine: "node /opt/pnpm icons:watch",
                currentWorkingDirectory: "/Users/test/staff-miniapp"
            )
        ]

        #expect(ProjectRuntimeProcessMatcher.matches(for: project, in: snapshots) == nil)
    }

    @Test
    func reportsAllDuplicateGroupsAndUsesTheLatestGroupLeader() {
        let project = Project(
            name: "staff-miniapp",
            path: "/Users/test/staff-miniapp",
            type: .miniApp,
            startCommand: "pnpm dev:weapp"
        )
        let snapshots = [
            ProjectProcessSnapshot(
                pid: 7000,
                processGroupID: 7000,
                commandLine: "node /opt/pnpm dev:weapp",
                currentWorkingDirectory: "/Users/test/staff-miniapp"
            ),
            ProjectProcessSnapshot(
                pid: 9000,
                processGroupID: 9000,
                commandLine: "node /opt/pnpm dev:weapp",
                currentWorkingDirectory: "/Users/test/staff-miniapp"
            )
        ]

        #expect(ProjectRuntimeProcessMatcher.matches(for: project, in: snapshots) == .init(
            representativePID: 9000,
            processGroupIDs: [7000, 9000]
        ))
    }

    @Test
    func ignoresMatchingCommandFromSiblingProject() {
        let project = Project(
            name: "staff-miniapp",
            path: "/Users/test/staff-miniapp",
            type: .miniApp,
            startCommand: "pnpm dev:weapp"
        )
        let snapshots = [
            ProjectProcessSnapshot(
                pid: 7911,
                processGroupID: 7911,
                commandLine: "node /opt/pnpm dev:weapp",
                currentWorkingDirectory: "/Users/test/staff-miniapp-docs"
            )
        ]

        #expect(ProjectRuntimeProcessMatcher.matches(for: project, in: snapshots) == nil)
    }

    @Test
    func nativeWeChatProjectIsNotInferredFromSharedDeveloperToolsProcesses() {
        let project = Project(
            name: "native-miniapp",
            path: "/Users/test/native-miniapp",
            type: .miniApp,
            runtimeKind: .weChatNative
        )
        let snapshots = [
            ProjectProcessSnapshot(
                pid: 41824,
                processGroupID: 41824,
                commandLine: "wechatwebdevtools --project /Users/test/native-miniapp",
                currentWorkingDirectory: "/Users/test/native-miniapp"
            )
        ]

        #expect(ProjectRuntimeProcessMatcher.matches(for: project, in: snapshots) == nil)
    }
}
