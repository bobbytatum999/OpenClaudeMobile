import Foundation

enum AppPersistence {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static var appSupportDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenClaudeMobile", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var sessionsURL: URL { appSupportDirectory.appendingPathComponent("sessions.json") }
    static var settingsURL: URL { appSupportDirectory.appendingPathComponent("settings.json") }
    static var documentsURL: URL { appSupportDirectory.appendingPathComponent("documents.json") }
    static var modelsDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var importedFilesDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func load<T: Decodable>(_ type: T.Type, from url: URL, default defaultValue: T) -> T {
        guard let data = try? Data(contentsOf: url) else { return defaultValue }
        return (try? decoder.decode(T.self, from: data)) ?? defaultValue
    }

    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }
}
