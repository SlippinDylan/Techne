import Foundation
import Testing
@testable import DevNexus

struct ProjectSnapshotMigrationTests {
    @Test
    func legacyProjectDecodesWithDefaultCommandSnapshot() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "legacy-app",
          "path": "/tmp/legacy-app",
          "type": "开发服务与实例",
          "currentBranch": "main",
          "startCommand": "pnpm dev",
          "addedDate": 0
        }
        """.data(using: .utf8)!

        let project = try JSONDecoder().decode(Project.self, from: json)

        #expect(project.startCommand == "pnpm dev")
        #expect(project.buildCommand == "")
        #expect(project.installCommand == "")
        #expect(project.commandProfileName == nil)
        #expect(project.installStrategy == .ifMissing)
    }
}
