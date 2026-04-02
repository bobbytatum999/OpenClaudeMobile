import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedTab: Tab = .chat

    enum Tab: Hashable {
        case chat, models, files, server, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView()
                .tabItem { Label("Chat", systemImage: "message.fill") }
                .tag(Tab.chat)

            ModelsView()
                .tabItem { Label("Models", systemImage: "cpu.fill") }
                .tag(Tab.models)
                .badge(model.installedModels.isEmpty ? "!" : nil)

            FilesView()
                .tabItem { Label("Files", systemImage: "folder.fill") }
                .tag(Tab.files)
                .badge(model.settings.selectedDocumentIDs.isEmpty ? nil : "\(model.settings.selectedDocumentIDs.count)")

            ServerView()
                .tabItem { Label("Server", systemImage: "server.rack") }
                .tag(Tab.server)
                .badge(model.isServerRunning ? "●" : nil)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .task { await model.bootstrap() }
        .tint(.accentColor)
    }
}
