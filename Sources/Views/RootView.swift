import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            NavigationStack {
                ChatView()
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
            }

            NavigationStack {
                ModelsView()
            }
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
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.06), Color.accentColor.opacity(0.10), Color.blue.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .overlay(alignment: .bottom) {
            Text(model.statusLine)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 68)
        }
    }
}
