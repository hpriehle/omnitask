import SwiftUI
import OmniTaskCore

struct ContentView: View {
    @EnvironmentObject var environment: AppEnvironmentiOS
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sun.max.fill")
                }
                .tag(0)

            AllTasksView()
                .tabItem {
                    Label("All Tasks", systemImage: "list.bullet")
                }
                .tag(1)

            ProjectsView()
                .tabItem {
                    Label("Projects", systemImage: "folder.fill")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppEnvironmentiOS())
}
