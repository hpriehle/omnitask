import SwiftUI
import Sparkle

/// Settings window content
struct SettingsView: View {
    @EnvironmentObject var environment: AppEnvironment
    @StateObject private var viewModel = SettingsViewModel()
    var projectVM: ProjectViewModel?

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            if let projectVM = projectVM {
                ProjectsSettingsView(projectVM: projectVM, tagRepository: environment.tagRepository)
                    .tabItem {
                        Label("Projects", systemImage: "folder")
                    }
            }

            apiTab
                .tabItem {
                    Label("AI", systemImage: "key")
                }

            shortcutsTab
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .padding(.top, 2)
        .onAppear {
            print("[SettingsView] appeared")
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)

                LabeledContent("Voice Input Key") {
                    Text("Option (\u{2325})")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Startup")
            }

            Section {
                LabeledContent("Version") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
                        .foregroundColor(.secondary)
                }

                Button {
                    environment.updaterController.checkForUpdates(nil)
                } label: {
                    Text("Check for Updates...")
                }
            } header: {
                Text("About")
            }

            Section {
                Button {
                    environment.hasCompletedOnboarding = false
                } label: {
                    Text("Show Onboarding Again")
                }
            } header: {
                Text("Onboarding")
            }

            Section {
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack {
                        Spacer()
                        Text("Quit OmniTask")
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - API Tab

    private var apiTab: some View {
        Form {
            Section {
                if viewModel.showAPIKeyField {
                    SecureField("API Key", text: $viewModel.claudeAPIKey)
                        .textFieldStyle(.roundedBorder)

                    Button("Hide") {
                        viewModel.showAPIKeyField = false
                    }
                } else {
                    HStack {
                        if viewModel.hasAPIKey {
                            Text(viewModel.maskedAPIKey)
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            Text("Not configured")
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(viewModel.hasAPIKey ? "Change" : "Add") {
                            viewModel.showAPIKeyField = true
                        }
                    }
                }

                Text("Get your API key from [console.anthropic.com](https://console.anthropic.com)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Claude API")
            } footer: {
                if viewModel.hasAPIKey {
                    Label("API key configured", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: viewModel.claudeAPIKey) { newValue in
            environment.claudeAPIKey = newValue
        }
    }

    // MARK: - Shortcuts Tab

    private var shortcutsTab: some View {
        Form {
            Section {
                ShortcutRecorderButton(shortcutName: .toggleOmniTask, label: "Toggle OmniTask")

                LabeledContent("Voice Input") {
                    Text("Hold Option (\u{2325})")
                        .foregroundColor(.secondary)
                }

                LabeledContent("New Task") {
                    Text("\u{2318}N")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Global Shortcuts")
            }

            Section {
                LabeledContent("Navigate Up") {
                    Text("↑")
                        .foregroundColor(.secondary)
                }

                LabeledContent("Navigate Down") {
                    Text("↓")
                        .foregroundColor(.secondary)
                }

                LabeledContent("Complete Selected") {
                    Text("\u{2318}\u{21A9}")
                        .foregroundColor(.secondary)
                }

                LabeledContent("Set as Current") {
                    Text("C")
                        .foregroundColor(.secondary)
                }

                LabeledContent("Add Subtask") {
                    Text("\u{2318}T")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Task Navigation")
            }

            Section {
                LabeledContent("Today") {
                    Text("\u{2318}1")
                        .foregroundColor(.secondary)
                }

                LabeledContent("All") {
                    Text("\u{2318}2")
                        .foregroundColor(.secondary)
                }

                LabeledContent("Project 1") {
                    Text("\u{2318}3")
                        .foregroundColor(.secondary)
                }

                LabeledContent("Project 2") {
                    Text("\u{2318}4")
                        .foregroundColor(.secondary)
                }

                Text("Continue with \u{2318}5-9 for more projects")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("View Navigation")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AppEnvironment())
}
