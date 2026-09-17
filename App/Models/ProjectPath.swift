import Foundation

enum ProjectPath {
    nonisolated static func canonical(_ rawPath: String) -> String {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.isEmpty == false else { return "" }

        let expandedPath = (trimmedPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }
}
