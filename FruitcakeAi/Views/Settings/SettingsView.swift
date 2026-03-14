//
//  SettingsView.swift
//  FruitcakeAi
//
//  Server URL configuration, current user info, backend status,
//  persona picker link, and sign-out.
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
    @State private var showPersonaPicker = false
    @State private var isSendingPushTest = false
    @State private var pushTestMessage: String?

    enum URLSaveState { case idle, saved, error }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                serverSection
                personaSection
                pushTestSection
                memoriesSection
                signOutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPersonaPicker) {
                PersonaPicker()
            }
            .onAppear {
                serverURLInput = authManager.serverURL?.absoluteString ?? ""
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
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
    }

    private var serverSection: some View {
        Section {
            TextField("http://192.168.1.x:8000", text: $serverURLInput)
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

            // Backend status row
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
            Text("Enter the IP address and port of your FruitcakeAI backend (e.g. http://192.168.1.100:8000).")
        }
    }

    private var personaSection: some View {
        Section("Persona") {
            Button {
                showPersonaPicker = true
            } label: {
                HStack {
                    Text("Browse personas")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private var memoriesSection: some View {
        Section("Assistant") {
            NavigationLink {
                MemoriesView()
                    .environment(authManager)
            } label: {
                Label("Memories", systemImage: "brain")
            }
        }
    }

    @ViewBuilder
    private var pushTestSection: some View {
        if authManager.currentUser?.isAdmin == true {
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
    }

    private var signOutSection: some View {
        Section {
            Button("Sign out", role: .destructive) {
                authManager.logout()
            }
        }
    }

    // MARK: - Actions

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

        // Persist to Keychain
        KeychainHelper.save(trimmed, forKey: KeychainHelper.Keys.serverURL)

        // Persist to SwiftData (upsert default ServerConfig)
        if let existing = savedServers.first(where: { $0.isDefault }) {
            existing.serverURL = trimmed
        } else {
            let config = ServerConfig(serverURL: trimmed, isDefault: true)
            modelContext.insert(config)
        }

        // Notify connectivity monitor to re-check
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

#Preview {
    SettingsView()
        .environment(AuthManager())
        .environment(ConnectivityMonitor(authManager: AuthManager()))
        .modelContainer(for: ServerConfig.self, inMemory: true)
}
