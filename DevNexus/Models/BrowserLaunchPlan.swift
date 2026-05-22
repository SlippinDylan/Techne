import Foundation

enum BrowserLaunchPlanningError: LocalizedError {
    case invalidURL(String)
    case missingProfileDirectory

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "无效的浏览器地址：\(url)"
        case .missingProfileDirectory:
            return "缺少浏览器实例目录"
        }
    }
}

struct BrowserLaunchPlan: Sendable, Equatable {
    let applicationURL: URL
    let arguments: [String]
    let urlsToOpen: [URL]
    let createsNewApplicationInstance: Bool
    let activates: Bool

    init(
        request: BrowserLaunchRequest,
        profileDirectoryURL: URL?,
        resolvedDebugPort: Int?
    ) throws {
        applicationURL = request.browser.appURL
        createsNewApplicationInstance = request.opensInNewInstance
        activates = true

        switch request.browser.type.engine {
        case .chromium:
            guard let profileDirectoryURL else {
                throw BrowserLaunchPlanningError.missingProfileDirectory
            }

            var arguments = [
                "--user-data-dir=\(profileDirectoryURL.path)",
                "--no-first-run",
                "--no-default-browser-check",
                "--new-window"
            ]

            if let resolvedDebugPort {
                arguments.insert("--remote-debugging-port=\(resolvedDebugPort)", at: 1)
            }

            if let normalizedURL = request.normalizedURL {
                arguments.append(normalizedURL)
            }

            self.arguments = arguments
            urlsToOpen = []

        case .safari:
            arguments = []

            if let normalizedURL = request.normalizedURL {
                guard let url = URL(string: normalizedURL) else {
                    throw BrowserLaunchPlanningError.invalidURL(normalizedURL)
                }
                urlsToOpen = [url]
            } else {
                urlsToOpen = []
            }
        }
    }
}
