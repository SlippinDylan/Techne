import Foundation
import Testing
@testable import Techne

struct ProjectStartupCoordinatorTests {
    @Test
    func ifMissingInstallsWhenPackageJSONExistsAndNodeModulesMissing() throws {
        let root = try makeProjectRoot(packageJSON: true, nodeModules: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProject(path: root.path, installStrategy: .ifMissing)

        #expect(ProjectStartupCoordinator.shouldInstallDependencies(for: project))
    }

    @Test
    func ifMissingSkipsInstallWhenNodeModulesExists() throws {
        let root = try makeProjectRoot(packageJSON: true, nodeModules: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProject(path: root.path, installStrategy: .ifMissing)

        #expect(ProjectStartupCoordinator.shouldInstallDependencies(for: project) == false)
    }

    @Test
    func alwaysInstallsWhenInstallCommandExists() throws {
        let root = try makeProjectRoot(packageJSON: false, nodeModules: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProject(path: root.path, installStrategy: .always)

        #expect(ProjectStartupCoordinator.shouldInstallDependencies(for: project))
    }

    @Test
    func neverSkipsInstallEvenWhenNodeModulesMissing() throws {
        let root = try makeProjectRoot(packageJSON: true, nodeModules: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProject(path: root.path, installStrategy: .never)

        #expect(ProjectStartupCoordinator.shouldInstallDependencies(for: project) == false)
    }

    @Test
    func missingInstallCommandSkipsInstallForAnyStrategy() throws {
        let root = try makeProjectRoot(packageJSON: true, nodeModules: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProject(
            path: root.path,
            installStrategy: .always,
            installCommand: "   "
        )

        #expect(ProjectStartupCoordinator.shouldInstallDependencies(for: project) == false)
    }

    @Test
    func executionPlanBuildsInstallCleanAndStartInOrder() throws {
        let root = try makeProjectRoot(packageJSON: true, nodeModules: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProject(
            path: root.path,
            installStrategy: .ifMissing,
            installCommand: "pnpm install --frozen-lockfile",
            cleanCommand: "rm -rf .cache",
            startCommand: "pnpm dev --host"
        )

        let plan = ProjectStartupCoordinator.makePlan(for: project, fallbackCleanCommand: "rm -rf tmp-cache")

        #expect(plan.shouldInstallDependencies)
        #expect(plan.phases == [
            .install(command: "pnpm install --frozen-lockfile"),
            .clean(command: "rm -rf .cache"),
            .start(command: "pnpm dev --host")
        ])
        #expect(plan.messages == [
            "[系统] 正在检查依赖...",
            "[系统] 检测到缺少依赖，准备执行安装命令: pnpm install --frozen-lockfile"
        ])
        #expect(plan.shellScript.contains("source ~/.zshrc 2>/dev/null || source ~/.bash_profile 2>/dev/null || source ~/.bashrc 2>/dev/null"))
        #expect(plan.shellScript.contains("cd \(ShellEscape.escape(root.path))"))
        #expect(plan.shellScript.contains("pnpm install --frozen-lockfile"))
        #expect(plan.shellScript.contains("rm -rf .cache"))
        #expect(plan.shellScript.contains("pnpm dev --host"))
        #expect(plan.shellScript.firstRange(of: "pnpm install --frozen-lockfile")!.lowerBound < plan.shellScript.firstRange(of: "rm -rf .cache")!.lowerBound)
        #expect(plan.shellScript.firstRange(of: "rm -rf .cache")!.lowerBound < plan.shellScript.firstRange(of: "pnpm dev --host")!.lowerBound)
    }

    @Test
    func executionPlanFallsBackToProvidedCleanCommandWhenProjectSnapshotIsEmpty() throws {
        let root = try makeProjectRoot(packageJSON: false, nodeModules: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProject(
            path: root.path,
            installStrategy: .never,
            cleanCommand: "",
            startCommand: "pnpm dev"
        )

        let plan = ProjectStartupCoordinator.makePlan(for: project, fallbackCleanCommand: "rm -rf .cache")

        #expect(plan.shouldInstallDependencies == false)
        #expect(plan.phases == [
            .clean(command: "rm -rf .cache"),
            .start(command: "pnpm dev")
        ])
    }

    @Test
    func controlSignalParsesWhenShellNoiseSharesTheSameLine() {
        let line = "shell banner \(ProjectStartupCoordinator.controlSignalPrefix)start"

        let event = ProjectStartupCoordinator.event(forControlLine: line)

        #expect(event == .phaseStarted(.start))
    }

    @Test
    func installFailureShortCircuitsBeforeStartCommand() async throws {
        let root = try makeProjectRoot(packageJSON: false, nodeModules: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProject(
            path: root.path,
            installStrategy: .always,
            installCommand: "touch install-ran && false",
            cleanCommand: "",
            startCommand: "touch start-ran"
        )

        let plan = ProjectStartupCoordinator.makePlan(for: project, fallbackCleanCommand: "")
        let result = try await ModernProcessExecutor.execute(
            command: plan.shellScript,
            in: root
        ) { _ in }

        #expect(result.exitCode != 0)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("install-ran").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("start-ran").path) == false)
    }

    @Test
    func cleanFailureShortCircuitsBeforeStartCommand() async throws {
        let root = try makeProjectRoot(packageJSON: false, nodeModules: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProject(
            path: root.path,
            installStrategy: .never,
            cleanCommand: "touch clean-ran && false",
            startCommand: "touch start-ran"
        )

        let plan = ProjectStartupCoordinator.makePlan(for: project, fallbackCleanCommand: "")
        let result = try await ModernProcessExecutor.execute(
            command: plan.shellScript,
            in: root
        ) { _ in }

        #expect(result.exitCode != 0)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("clean-ran").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("start-ran").path) == false)
    }

    private func makeProject(
        path: String,
        installStrategy: InstallStrategy,
        installCommand: String = "pnpm install",
        cleanCommand: String = "rm -rf dist",
        startCommand: String = "pnpm dev"
    ) -> Project {
        Project(
            name: "frontend-app",
            path: path,
            type: .devServer,
            currentBranch: "main",
            startCommand: startCommand,
            buildCommand: "",
            cleanCommand: cleanCommand,
            installCommand: installCommand,
            stopCommand: "",
            discardChangesCommand: "",
            commandProfileName: "Vite",
            installStrategy: installStrategy
        )
    }

    private func makeProjectRoot(packageJSON: Bool, nodeModules: Bool) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        if packageJSON {
            try "{}".write(to: root.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        }

        if nodeModules {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("node_modules"),
                withIntermediateDirectories: true
            )
        }

        return root
    }
}
