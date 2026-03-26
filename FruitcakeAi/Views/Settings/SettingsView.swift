//
//  SettingsView.swift
//  FruitcakeAi
//
//  Category-driven settings navigation with adaptive sidebar/detail behavior.
//

import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(AuthManager.self) private var authManager
    @Environment(ConnectivityMonitor.self) private var connectivity
    @Environment(\.modelContext) private var modelContext

    @Query private var savedServers: [ServerConfig]

    @State private var serverURLInput: String = ""
    @State private var urlSaveState: URLSaveState = .idle
    @State private var selection: SettingsDestination? = .account
    @State private var isSendingPushTest = false
    @State private var pushTestMessage: String?

    enum URLSaveState { case idle, saved, error }

    var body: some View {
        NavigationSplitView {
            settingsSidebar
        } detail: {
            NavigationStack {
                settingsDetail
            }
        }
        .onAppear {
            serverURLInput = authManager.serverURL?.absoluteString ?? ""
            normalizeSelection()
        }
        .onChange(of: authManager.currentUser?.isAdmin == true) { _, _ in
            normalizeSelection()
        }
    }

    private var settingsSidebar: some View {
        List(selection: $selection) {
            Section("General") {
                settingsLink("Account", systemImage: "person.crop.circle", destination: .account)
                settingsLink("Server", systemImage: "externaldrive.connected.to.line.below", destination: .server)
                if authManager.currentUser?.isAdmin == true {
                    settingsLink("Push Testing", systemImage: "bell.badge", destination: .pushTesting)
                }
            }

            Section("Personas") {
                settingsLink("Personas", systemImage: "person.3", destination: .personas)
            }

            Section("Assistant") {
                settingsLink("Routing", systemImage: "point.3.connected.trianglepath.dotted", destination: .routing)
                settingsLink("Secrets", systemImage: "key", destination: .secrets)
                settingsLink("Memories", systemImage: "brain", destination: .memories)
                settingsLink("Token Usage", systemImage: "number.circle", destination: .tokenUsage)
            }
        }
        .navigationTitle("Settings")
    }

    private func settingsLink(_ title: String, systemImage: String, destination: SettingsDestination) -> some View {
        NavigationLink(value: destination) {
            Label(title, systemImage: systemImage)
        }
    }

    @ViewBuilder
    private var settingsDetail: some View {
        switch selection ?? .account {
        case .account:
            accountDetail
        case .server:
            serverDetail
        case .pushTesting:
            if authManager.currentUser?.isAdmin == true {
                pushTestingDetail
            } else {
                accountDetail
            }
        case .personas:
            PersonaPicker(embedded: true)
                .environment(authManager)
        case .routing:
            ChatRoutingView()
                .environment(authManager)
        case .secrets:
            SecretsView()
                .environment(authManager)
        case .memories:
            MemoriesView()
                .environment(authManager)
        case .tokenUsage:
            TokenUsageView()
                .environment(authManager)
        }
    }

    private var accountDetail: some View {
        Form {
            Section("Account") {
                if let user = authManager.currentUser {
                    LabeledContent("Username", value: user.username)
                    LabeledContent("Email", value: user.email)
                    LabeledContent("Role", value: user.role.capitalized)
                    LabeledContent(
                        "Persona",
                        value: user.persona
                            .replacingOccurrences(of: "_", with: " ")
                            .capitalized
                    )
                } else {
                    Text("Not signed in")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Sign out", role: .destructive) {
                    authManager.logout()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Account")
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
    }

    private var serverDetail: some View {
        Form {
            Section {
                TextField("http://192.168.1.x:30417", text: $serverURLInput)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif

                Button {
                    saveServerURL()
                } label: {
                    switch urlSaveState {
                    case .idle:
                        Label("Save", systemImage: "checkmark")
                    case .saved:
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .error:
                        Label("Invalid URL", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                }
                .disabled(serverURLInput.isEmpty || urlSaveState == .saved)

                HStack {
                    Image(systemName: connectivity.isBackendReachable
                          ? "checkmark.circle.fill"
                          : "xmark.circle.fill")
                        .foregroundStyle(connectivity.isBackendReachable ? .green : .red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectivity.isBackendReachable ? "Connected" : "Offline")
                            .font(.body)
                        if let last = connectivity.lastChecked {
                            Text("Last checked \(last.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    Button("Check") { connectivity.checkNow() }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
            } header: {
                Text("Server")
            } footer: {
                Text("Enter the IP address and port of your FruitcakeAI backend (e.g. http://192.168.1.100:30417).")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Server")
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var pushTestingDetail: some View {
        Form {
            Section("Push Testing") {
                Button {
                    Task { await sendPushTest() }
                } label: {
                    if isSendingPushTest {
                        ProgressView()
                    } else {
                        Label("Send Test Push", systemImage: "bell.badge")
                    }
                }
                .disabled(isSendingPushTest)

                if let pushTestMessage {
                    Text(pushTestMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Push Testing")
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
    }

    private func normalizeSelection() {
        if selection == .pushTesting, authManager.currentUser?.isAdmin != true {
            selection = .account
        }
        if selection == nil {
            selection = .account
        }
    }

    private func saveServerURL() {
        let trimmed = serverURLInput.trimmingCharacters(in: .whitespaces)
        guard let _ = URL(string: trimmed), trimmed.hasPrefix("http") else {
            urlSaveState = .error
            Task {
                try? await Task.sleep(for: .seconds(2))
                urlSaveState = .idle
            }
            return
        }

        KeychainHelper.save(trimmed, forKey: KeychainHelper.Keys.serverURL)

        if let existing = savedServers.first(where: { $0.isDefault }) {
            existing.serverURL = trimmed
        } else {
            let config = ServerConfig(serverURL: trimmed, isDefault: true)
            modelContext.insert(config)
        }

        connectivity.checkNow()

        urlSaveState = .saved
        Task {
            try? await Task.sleep(for: .seconds(2))
            urlSaveState = .idle
        }
    }

    private func sendPushTest() async {
        isSendingPushTest = true
        defer { isSendingPushTest = false }

        do {
            let api = APIClient(authManager: authManager)
            let message = try await api.sendTestPush(
                title: "Fruitcake Test Push",
                body: "Manual test from Settings."
            )
            pushTestMessage = message
        } catch {
            pushTestMessage = "Push test failed: \(error.localizedDescription)"
        }
    }
}

private enum SettingsDestination: String, Hashable, CaseIterable {
    case account
    case server
    case pushTesting
    case personas
    case routing
    case secrets
    case memories
    case tokenUsage
}

#Preview {
    SettingsView()
        .environment(AuthManager())
        .environment(ConnectivityMonitor(authManager: AuthManager()))
        .modelContainer(for: ServerConfig.self, inMemory: true)
}
