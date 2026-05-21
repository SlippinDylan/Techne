import Foundation
import Testing
@testable import DevNexus

struct BrowserLaunchPlanTests {
    @Test
    func chromiumPlanOmitsURLWhenLaunchingStandaloneInstance() throws {
        let browser = Browser(
            type: .chrome,
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            isDefault: false
        )
        let request = BrowserLaunchRequest.devServer(
            browser: browser,
            port: 4173,
            projectPath: "/Users/test/project",
            shouldOpenURL: false,
            launchSource: "discovered-server"
        )

        let profileDirectoryURL = URL(fileURLWithPath: "/tmp/devnexus-tests/profile-1")
        let plan = try BrowserLaunchPlan(
            request: request,
            profileDirectoryURL: profileDirectoryURL,
            resolvedDebugPort: 9333
        )

        #expect(plan.applicationURL == browser.appURL)
        #expect(plan.arguments.contains("--user-data-dir=\(profileDirectoryURL.path)"))
        #expect(plan.arguments.contains("--remote-debugging-port=9333"))
        #expect(plan.arguments.contains("--no-first-run"))
        #expect(plan.arguments.contains("--no-default-browser-check"))
        #expect(plan.arguments.contains("http://localhost:4173") == false)
        #expect(plan.urlsToOpen.isEmpty)
        #expect(plan.createsNewApplicationInstance)
        #expect(plan.activates)
    }

    @Test
    func safariPlanUsesURLPayloadWithoutChromiumFlags() throws {
        let browser = Browser(
            type: .safari,
            appURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            isDefault: false
        )
        let request = BrowserLaunchRequest.devServer(
            browser: browser,
            port: 3000,
            projectPath: "/Users/test/project",
            shouldOpenURL: true,
            launchSource: "project-card"
        )

        let plan = try BrowserLaunchPlan(
            request: request,
            profileDirectoryURL: nil,
            resolvedDebugPort: nil
        )

        #expect(plan.applicationURL == browser.appURL)
        #expect(plan.arguments.isEmpty)
        #expect(plan.urlsToOpen.map(\.absoluteString) == ["http://localhost:3000"])
        #expect(plan.createsNewApplicationInstance == false)
    }
}

struct BrowserLaunchServiceTests {
    @MainActor
    @Test
    func findAvailablePortReturnsStartingPortWhenItIsFree() throws {
        let port = try Self.makeUnusedTCPPort()
        let service = BrowserLaunchService()

        #expect(service.findAvailablePort(startingFrom: port) == port)
    }

    @MainActor
    @Test
    func isPortAvailableReturnsFalseForListeningPort() throws {
        let listener = try TCPTestListener()
        defer { listener.close() }

        let service = BrowserLaunchService()

        #expect(service.isPortAvailable(listener.port) == false)
    }

    private static func makeUnusedTCPPort() throws -> Int {
        let listener = try TCPTestListener()
        let port = listener.port
        listener.close()
        return port
    }
}

private final class TCPTestListener {
    let socketFD: Int32
    let port: Int
    private var isClosed = false

    init() throws {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw POSIXError(.EIO)
        }

        var reuseAddress: Int32 = 1
        guard setsockopt(
            socketFD,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout.size(ofValue: reuseAddress))
        ) == 0 else {
            let error = POSIXErrorCode(rawValue: errno) ?? .EIO
            Darwin.close(socketFD)
            throw POSIXError(error)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
        address.sin_port = 0

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            let error = POSIXErrorCode(rawValue: errno) ?? .EIO
            Darwin.close(socketFD)
            throw POSIXError(error)
        }

        guard listen(socketFD, 1) == 0 else {
            let error = POSIXErrorCode(rawValue: errno) ?? .EIO
            Darwin.close(socketFD)
            throw POSIXError(error)
        }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(socketFD, sockaddrPointer, &length)
            }
        }

        guard nameResult == 0 else {
            let error = POSIXErrorCode(rawValue: errno) ?? .EIO
            Darwin.close(socketFD)
            throw POSIXError(error)
        }

        self.socketFD = socketFD
        self.port = Int(UInt16(bigEndian: boundAddress.sin_port))
    }

    func close() {
        guard isClosed == false else {
            return
        }

        isClosed = true
        Darwin.close(socketFD)
    }

    deinit {
        Darwin.close(socketFD)
    }
}
