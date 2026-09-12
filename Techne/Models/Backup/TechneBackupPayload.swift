import Foundation

struct TechneBackupPayload: Codable, Sendable {
    var schemaVersion: Int
    var exportedAt: Date
    var appVersion: String
    var projects: [Project]
    var commandConfigs: [CommandConfig]

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case exportedAt
        case appVersion
        case projects
        case commandConfigs
    }

    nonisolated init(
        schemaVersion: Int,
        exportedAt: Date,
        appVersion: String,
        projects: [Project],
        commandConfigs: [CommandConfig]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.projects = projects
        self.commandConfigs = commandConfigs
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        self.appVersion = try container.decode(String.self, forKey: .appVersion)
        self.projects = try container.decode([Project].self, forKey: .projects)
        self.commandConfigs = try container.decode([CommandConfig].self, forKey: .commandConfigs)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(projects, forKey: .projects)
        try container.encode(commandConfigs, forKey: .commandConfigs)
    }
}
