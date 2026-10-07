import SwiftUI

struct ModelProfilesView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var profiles: [AssistantModelProfile] = []
    @State private var editingProfile: AssistantModelProfile?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        SettingsPage(title: "Model Profiles", subtitle: "Control capabilities and runtime behavior without restarting the Fruitcake server.") {
            if isLoading {
                ProgressView("Loading model profiles…")
            } else if profiles.isEmpty {
                SettingsCard(title: "No profiles", systemImage: "cpu") {
                    Text("No configured model profiles were returned by the server.")
                        .foregroundStyle(Theme.textDim)
                }
            } else {
                ForEach(profiles) { profile in
                    modelCard(profile)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task { await load() }
        .sheet(item: $editingProfile) { profile in
            ModelProfileEditor(profile: profile) { patch in
                await save(profile, patch: patch)
            }
        }
    }

    private func modelCard(_ profile: AssistantModelProfile) -> some View {
        SettingsCard(title: profile.displayName, systemImage: profile.isLocal ? "desktopcomputer" : "cloud") {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.modelId)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textDim)
                    HStack(spacing: 7) {
                        SettingsCapabilityChip(label: profile.enabled ? "ENABLED" : "DISABLED", enabled: profile.enabled)
                        SettingsCapabilityChip(label: "TOOLS", enabled: profile.capabilities.tools)
                        SettingsCapabilityChip(label: "VISION", enabled: profile.capabilities.vision)
                        SettingsCapabilityChip(label: "THINKING", enabled: profile.capabilities.thinking)
                        SettingsCapabilityChip(label: "STREAM", enabled: profile.capabilities.nativeStreaming)
                    }
                }
                Spacer()
                Text(profile.toolMode.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(Theme.mono(9, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
                Button("Edit") { editingProfile = profile }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            profiles = try await APIClient(authManager: authManager).fetchAdminModelProfiles()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func save(
        _ profile: AssistantModelProfile,
        patch: AdminModelProfilePatch
    ) async -> Bool {
        do {
            let updated = try await APIClient(authManager: authManager)
                .updateAdminModelProfile(profile.profileId, patch: patch)
            if let index = profiles.firstIndex(where: { $0.profileId == updated.profileId }) {
                profiles[index] = updated
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct ModelProfileEditor: View {
    @Environment(\.dismiss) private var dismiss

    let profile: AssistantModelProfile
    let save: (AdminModelProfilePatch) async -> Bool

    @State private var displayName: String
    @State private var enabled: Bool
    @State private var supportsText: Bool
    @State private var supportsVision: Bool
    @State private var supportsTools: Bool
    @State private var supportsThinking: Bool
    @State private var supportsNativeStreaming: Bool
    @State private var reasoningEfforts: String
    @State private var defaultReasoningEffort: String
    @State private var toolMode: String
    @State private var allowedTools: String
    @State private var blockedTools: String
    @State private var keepAlive: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        profile: AssistantModelProfile,
        save: @escaping (AdminModelProfilePatch) async -> Bool
    ) {
        self.profile = profile
        self.save = save
        _displayName = State(initialValue: profile.displayName)
        _enabled = State(initialValue: profile.enabled)
        _supportsText = State(initialValue: profile.capabilities.text)
        _supportsVision = State(initialValue: profile.capabilities.vision)
        _supportsTools = State(initialValue: profile.capabilities.tools)
        _supportsThinking = State(initialValue: profile.capabilities.thinking)
        _supportsNativeStreaming = State(initialValue: profile.capabilities.nativeStreaming)
        _reasoningEfforts = State(initialValue: profile.reasoningEfforts.joined(separator: ", "))
        _defaultReasoningEffort = State(initialValue: profile.defaultReasoningEffort ?? "")
        _toolMode = State(initialValue: profile.toolMode)
        _allowedTools = State(initialValue: profile.allowedTools.joined(separator: ", "))
        _blockedTools = State(initialValue: profile.blockedTools.joined(separator: ", "))
        _keepAlive = State(initialValue: profile.keepAlive ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    LabeledContent("Model ID", value: profile.modelId)
                    LabeledContent("Provider", value: profile.providerFamily.capitalized)
                    TextField("Display name", text: $displayName)
                    Toggle("Enabled", isOn: $enabled)
                }

                Section("Capabilities") {
                    Toggle("Text", isOn: $supportsText)
                    Toggle("Vision", isOn: $supportsVision)
                    Toggle("Tool calling", isOn: $supportsTools)
                        .onChange(of: supportsTools) { _, value in
                            if !value { toolMode = "text_only" }
                        }
                    Toggle("Thinking controls", isOn: $supportsThinking)
                    Toggle("Native streaming", isOn: $supportsNativeStreaming)
                }

                Section("Reasoning") {
                    TextField("Supported values · low, medium, xhigh", text: $reasoningEfforts)
                    TextField("Default value", text: $defaultReasoningEffort)
                }
                .disabled(!supportsThinking)

                Section("Tools") {
                    Picker("Mode", selection: $toolMode) {
                        Text("Enabled").tag("enabled")
                        Text("Text only").tag("text_only")
                        Text("Restricted").tag("restricted")
                    }
                    TextField("Allowed tools · comma separated", text: $allowedTools)
                    TextField("Blocked tools · comma separated", text: $blockedTools)
                }

                Section("Local runtime") {
                    TextField("Keep alive · e.g. 30m", text: $keepAlive)
                        .disabled(!profile.isLocal)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Model Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await submit() } }
                        .disabled(isSaving || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 540, minHeight: 650)
    }

    private func submit() async {
        isSaving = true
        errorMessage = nil
        let efforts = values(from: reasoningEfforts)
        let normalizedDefault = defaultReasoningEffort.trimmingCharacters(in: .whitespaces)
        guard normalizedDefault.isEmpty || efforts.contains(normalizedDefault) else {
            errorMessage = "The default reasoning value must appear in the supported values list."
            isSaving = false
            return
        }
        let succeeded = await save(AdminModelProfilePatch(
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            enabled: enabled,
            supportsText: supportsText,
            supportsVision: supportsVision,
            supportsTools: supportsTools,
            supportsThinking: supportsThinking,
            supportsNativeStreaming: supportsNativeStreaming,
            reasoningEfforts: supportsThinking ? efforts : [],
            defaultReasoningEffort: supportsThinking ? normalizedDefault : "",
            toolMode: supportsTools ? toolMode : "text_only",
            allowedTools: values(from: allowedTools),
            blockedTools: values(from: blockedTools),
            keepAlive: keepAlive.trimmingCharacters(in: .whitespaces)
        ))
        isSaving = false
        if succeeded { dismiss() }
    }

    private func values(from text: String) -> [String] {
        Array(Set(text.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()
    }
}
