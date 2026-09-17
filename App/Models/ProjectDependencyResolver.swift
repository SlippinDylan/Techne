import CryptoKit
import Foundation

struct ProjectDependencyState: Equatable, Sendable {
    let workspaceRootPath: String
    let fingerprint: String?
    let hasInstallArtifact: Bool
}

enum ProjectDependencyResolver {
    private static let lockfileNames = [
        "npm-shrinkwrap.json",
        "package-lock.json",
        "pnpm-lock.yaml",
        "yarn.lock",
        "bun.lock",
        "bun.lockb"
    ]
    private static let configurationNames = [
        "pnpm-workspace.yaml",
        ".npmrc",
        ".yarnrc.yml",
        "bunfig.toml"
    ]

    static func state(
        at projectPath: String,
        fileManager: FileManager = .default
    ) -> ProjectDependencyState {
        let projectURL = URL(fileURLWithPath: projectPath).standardizedFileURL
        let workspaceRootURL = workspaceRoot(for: projectURL, fileManager: fileManager)
        let fingerprint = dependencyFingerprint(
            projectURL: projectURL,
            workspaceRootURL: workspaceRootURL,
            fileManager: fileManager
        )
        let isYarn = usesYarn(at: workspaceRootURL, projectURL: projectURL, fileManager: fileManager)
        let nodeModules = workspaceRootURL.appendingPathComponent("node_modules").path
        let yarnPnP = workspaceRootURL.appendingPathComponent(".pnp.cjs").path
        let hasInstallArtifact = fileManager.fileExists(atPath: nodeModules) ||
            isYarn && fileManager.fileExists(atPath: yarnPnP)

        return ProjectDependencyState(
            workspaceRootPath: workspaceRootURL.path,
            fingerprint: fingerprint,
            hasInstallArtifact: hasInstallArtifact
        )
    }

    private static func workspaceRoot(for projectURL: URL, fileManager: FileManager) -> URL {
        if containsLockfile(at: projectURL, fileManager: fileManager) ||
            isWorkspaceManifest(at: projectURL, fileManager: fileManager) {
            return projectURL
        }
        if fileManager.fileExists(atPath: projectURL.appendingPathComponent(".git").path) {
            return projectURL
        }

        var candidate = projectURL.deletingLastPathComponent()
        while candidate.path != candidate.deletingLastPathComponent().path {
            if isWorkspaceManifest(at: candidate, fileManager: fileManager) {
                return candidate
            }
            if fileManager.fileExists(atPath: candidate.appendingPathComponent(".git").path) {
                break
            }
            candidate.deleteLastPathComponent()
        }

        return projectURL
    }

    private static func isWorkspaceManifest(at directoryURL: URL, fileManager: FileManager) -> Bool {
        if fileManager.fileExists(atPath: directoryURL.appendingPathComponent("pnpm-workspace.yaml").path) {
            return true
        }

        let packageJSONURL = directoryURL.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageJSONURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["workspaces"] != nil
    }

    private static func containsLockfile(at directoryURL: URL, fileManager: FileManager) -> Bool {
        lockfileNames.contains { name in
            fileManager.fileExists(atPath: directoryURL.appendingPathComponent(name).path)
        }
    }

    private static func usesYarn(
        at workspaceRootURL: URL,
        projectURL: URL,
        fileManager: FileManager
    ) -> Bool {
        if fileManager.fileExists(atPath: workspaceRootURL.appendingPathComponent("yarn.lock").path) {
            return true
        }

        for directoryURL in [projectURL, workspaceRootURL] {
            let packageJSONURL = directoryURL.appendingPathComponent("package.json")
            guard let data = try? Data(contentsOf: packageJSONURL),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let packageManager = object["packageManager"] as? String else {
                continue
            }
            if packageManager.hasPrefix("yarn@") {
                return true
            }
        }

        return false
    }

    private static func dependencyFingerprint(
        projectURL: URL,
        workspaceRootURL: URL,
        fileManager: FileManager
    ) -> String? {
        let rootPackageJSON = workspaceRootURL.appendingPathComponent("package.json")
        guard fileManager.fileExists(atPath: rootPackageJSON.path) else {
            return nil
        }

        var records: [(String, URL)] = [("root/package.json", rootPackageJSON)]
        if projectURL.path != workspaceRootURL.path {
            records.append(("project/package.json", projectURL.appendingPathComponent("package.json")))
        }
        records.append(contentsOf: (lockfileNames + configurationNames).map { name in
            ("root/\(name)", workspaceRootURL.appendingPathComponent(name))
        })

        var hasher = SHA256()
        hasher.update(data: Data("techne-dependencies-v1\n".utf8))
        for (name, url) in records {
            hasher.update(data: Data("\(name)\n".utf8))
            if let data = try? Data(contentsOf: url) {
                hasher.update(data: data)
            } else {
                hasher.update(data: Data("<absent>".utf8))
            }
            hasher.update(data: Data("\n".utf8))
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
