import Foundation

struct AppPersistence {
    static let shared = AppPersistence()
    
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    static var workspaceDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("OpenClaude", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    static var modelsDirectory: URL {
        let url = workspaceDirectory.appendingPathComponent("Models", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    static var importedFilesDirectory: URL {
        let url = workspaceDirectory.appendingPathComponent("ImportedFiles", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    static var settingsURL: URL {
        workspaceDirectory.appendingPathComponent("settings.json")
    }
    
    static var sessionsURL: URL {
        workspaceDirectory.appendingPathComponent("sessions.json")
    }
    
    static var documentsURL: URL {
        workspaceDirectory.appendingPathComponent("documents.json")
    }
    
    static func save<T: Encodable>(_ object: T, to url: URL) throws {
        let data = try JSONEncoder().encode(object)
        try data.write(to: url, options: .atomic)
    }
    
    static func load<T: Decodable>(_ type: T.Type, from url: URL, default: T) -> T {
        guard let data = try? Data(contentsOf: url) else { return `default` }
        return (try? JSONDecoder().decode(type, from: data)) ?? `default`
    }
}
