import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                }

            ModelsView()
                .tabItem {
                    Label("Models", systemImage: "cube.box.fill")
                }

            NavigationStack {
                FilesView()
            }
            .tabItem {
                Label("Files", systemImage: "doc.text.fill")
            }

            NavigationStack {
                ServerView()
            }
            .tabItem {
                Label("Server", systemImage: "server.rack")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
    }
}
