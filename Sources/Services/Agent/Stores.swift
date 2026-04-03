import Foundation

actor ChatStore {
    func loadSessions() -> [ChatSession] {
        AppPersistence.load([ChatSession].self, from: AppPersistence.sessionsURL, default: [ChatSession()])
    }

    func saveSessions(_ sessions: [ChatSession]) {
        try? AppPersistence.save(sessions, to: AppPersistence.sessionsURL)
    }
}

struct SettingsStore {
    func load() -> AppSettings {
        AppPersistence.load(AppSettings.self, from: AppPersistence.settingsURL, default: .default)
    }

    func save(_ settings: AppSettings) throws {
        try AppPersistence.save(settings, to: AppPersistence.settingsURL)
    }
}
