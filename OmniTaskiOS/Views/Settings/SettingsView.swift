import SwiftUI
import OmniTaskCore

struct SettingsView: View {
    @EnvironmentObject var environment: AppEnvironmentiOS
    @State private var apiKey = ""
    @State private var showingAPIKeyAlert = false

    var body: some View {
        NavigationStack {
            Form {
                // Sync Status Section
                Section {
                    HStack {
                        Image(systemName: "icloud")
                            .foregroundColor(.blue)
                        Text("iCloud Sync")
                        Spacer()
                        if environment.cloudKitSyncService.isSyncing {
                            ProgressView()
                        } else if environment.cloudKitSyncService.syncError != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }

                    if let lastSync = environment.cloudKitSyncService.lastSyncDate {
                        HStack {
                            Text("Last synced")
                            Spacer()
                            Text(lastSync, style: .relative)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let error = environment.cloudKitSyncService.syncError {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Button("Sync Now") {
                        Task {
                            await environment.cloudKitSyncService.sync()
                        }
                    }
                    .disabled(environment.cloudKitSyncService.isSyncing)
                } header: {
                    Text("Sync")
                }

                // AI Section
                Section {
                    SecureField("API Key", text: $apiKey)
                        .onAppear {
                            apiKey = environment.claudeAPIKey
                        }
                        .onChange(of: apiKey) { _, newValue in
                            environment.claudeAPIKey = newValue
                        }

                    Button("Get API Key") {
                        if let url = URL(string: "https://console.anthropic.com/api-keys") {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("Claude AI")
                } footer: {
                    Text("Enter your Claude API key to enable AI task parsing. Your key is stored securely on your device.")
                }

                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://omnitask.app")!) {
                        HStack {
                            Text("Website")
                            Spacer()
                            Image(systemName: "safari")
                                .foregroundColor(.secondary)
                        }
                    }

                    Link(destination: URL(string: "mailto:support@omnitask.app")!) {
                        HStack {
                            Text("Contact Support")
                            Spacer()
                            Image(systemName: "envelope")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("About")
                }

                // Danger Zone
                Section {
                    Button("Clear Completed Tasks", role: .destructive) {
                        clearCompletedTasks()
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Permanently delete all completed tasks. This cannot be undone.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func clearCompletedTasks() {
        Task {
            let completedTasks = environment.taskRepository.tasks.filter { $0.isCompleted }
            for task in completedTasks {
                try? await environment.taskRepository.delete(task)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppEnvironmentiOS())
}
