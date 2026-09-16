import SwiftUI
import UniformTypeIdentifiers

struct TechneBackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var payload: TechneBackupPayload

    init(payload: TechneBackupPayload) {
        self.payload = payload
    }

    init(data: Data) throws {
        payload = try Self.makeDecoder().decode(TechneBackupPayload.self, from: data)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self = try .init(data: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        .init(regularFileWithContents: try serializedData())
    }

    func serializedData() throws -> Data {
        try Self.makeEncoder().encode(payload)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
