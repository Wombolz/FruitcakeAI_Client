import SwiftUI

struct AssistantPreferencesView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var settings: UserAssistantSettings?
    @State private var models: [AssistantModelProfile] = []
    @State private var selectedModelProfileID = ""
    @State private var selectedVisionProfileID = ""
    @State private var selectedReasoning = ""
    @State private var selectedRouting = "auto"
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    private var selectedModel: AssistantModelProfile? {
        models.first { $0.profileId == selectedModelProfileID }
    }

    private var visionModels: [AssistantModelProfile] {
        models.filter { $0.capabilities.vision }
    }

    var body: some View {
        SettingsPage(title: "Chat & Models", subtitle: "Choose how your assistant responds. Changes apply to new chats and the next eligible request.") {
            if isLoading {
                ProgressView("Loading model preferences…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                SettingsCard(title: "Default model", systemImage: "cpu") {
                    Picker("Chat model", selection: $selectedModelProfileID) {
                        ForEach(models) { model in
                            Text("\(model.displayName) · \(model.providerLabel)")
                                .tag(model.profileId)
                        }
                    }
                    .onChange(of: selectedModelProfileID) { _, _ in
                        normalizeReasoningSelection()
                    }

                    if let selectedModel {
                        capabilityLine(for: selectedModel)
                    }

                    if let settings {
                        SettingsSourceLabel(source: settings.modelProfileId.source)
                    }
                }

                if let selectedModel, selectedModel.capabilities.thinking,
                   !selectedModel.reasoningEfforts.isEmpty {
                    SettingsCard(title: "Reasoning", systemImage: "sparkles") {
                        Picker("Effort", selection: $selectedReasoning) {
                            ForEach(selectedModel.reasoningEfforts, id: \.self) { effort in
                                Text(effort.capitalized).tag(effort)
                            }
                        }
                        Text("Only options supported by this model are shown.")
                            .font(.caption)
                            .foregroundStyle(Theme.textDim)
                    }
                }

                SettingsCard(title: "Chat routing", systemImage: "point.3.connected.trianglepath.dotted") {
                    Picker("Mode", selection: $selectedRouting) {
                        Text("Automatic").tag("auto")
                        Text("Fast").tag("fast")
                        Text("Deep").tag("deep")
                    }
                    Text(routingDescription)
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                }

                SettingsCard(title: "Vision", systemImage: "eye") {
                    if visionModels.isEmpty {
                        Text("No enabled model currently advertises image understanding.")
                            .foregroundStyle(Theme.textDim)
                    } else {
                        Picker("Image model", selection: $selectedVisionProfileID) {
                            ForEach(visionModels) { model in
                                Text(model.displayName).tag(model.profileId)
                            }
                        }
                    }
                }

                actionRow
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func capabilityLine(for model: AssistantModelProfile) -> some View {
        HStack(spacing: 8) {
            SettingsCapabilityChip(label: model.isLocal ? "LOCAL" : "CLOUD", enabled: true)
            SettingsCapabilityChip(label: "TOOLS", enabled: model.capabilities.tools)
            SettingsCapabilityChip(label: "VISION", enabled: model.capabilities.vision)
            SettingsCapabilityChip(label: "STREAM", enabled: model.capabilities.nativeStreaming)
            Spacer()
        }
    }

    private var actionRow: some View {
        HStack {
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            } else if let savedMessage {
                Text(savedMessage).font(.caption).foregroundStyle(Theme.ok)
            }
            Spacer()
            Button("Save Changes") { Task { await save() } }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || selectedModelProfileID.isEmpty)
        }
    }

    private var routingDescription: String {
        switch selectedRouting {
        case "fast": return "Prefer the direct chat path for lower latency."
        case "deep": return "Prefer multi-step orchestration for complex research and tool use."
        default: return "Let Fruitcake choose the path based on the request."
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let api = APIClient(authManager: authManager)
            async let loadedSettings = api.fetchUserAssistantSettings()
            async let loadedModels = api.fetchAssistantModelProfiles()
            let (settings, models) = try await (loadedSettings, loadedModels)
            self.settings = settings
            self.models = models
            selectedModelProfileID = settings.modelProfileId.value
                ?? models.first(where: { $0.modelId == settings.defaultChatModel.value })?.profileId
                ?? models.first?.profileId
                ?? ""
            selectedVisionProfileID = settings.visionModelProfileId.value
                ?? models.first(where: { $0.modelId == settings.defaultVisionModel.value })?.profileId
                ?? models.first(where: { $0.capabilities.vision })?.profileId
                ?? ""
            selectedRouting = settings.chatRoutingPreference.value ?? "auto"
            selectedReasoning = settings.reasoningEffort.value ?? ""
            normalizeReasoningSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func normalizeReasoningSelection() {
        guard let selectedModel else {
            selectedReasoning = ""
            return
        }
        if !selectedModel.reasoningEfforts.contains(selectedReasoning) {
            selectedReasoning = selectedModel.defaultReasoningEffort
                ?? selectedModel.reasoningEfforts.first
                ?? ""
        }
    }

    private func save() async {
        guard let settings else { return }
        isSaving = true
        errorMessage = nil
        savedMessage = nil
        defer { isSaving = false }
        do {
            let patch = UserAssistantSettingsPatch(
                expectedVersion: settings.version,
                preferredModelProfileId: selectedModelProfileID,
                preferredVisionModelProfileId: selectedVisionProfileID.isEmpty ? nil : selectedVisionProfileID,
                preferredReasoningEffort: selectedReasoning.isEmpty ? nil : selectedReasoning,
                chatRoutingPreference: selectedRouting
            )
            self.settings = try await APIClient(authManager: authManager)
                .updateUserAssistantSettings(patch)
            try await authManager.refreshCurrentUser()
            savedMessage = "Saved"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PersonalExperienceSettingsView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var settings: UserAssistantSettings?
    @State private var timezone = TimeZone.current.identifier
    @State private var activeStart = ""
    @State private var activeEnd = ""
    @State private var notificationsEnabled = true
    @State private var deliveryEnabled = true
    @State private var appearance = "system"
    @State private var reduceMotion = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        SettingsPage(title: "Experience", subtitle: "Set delivery windows, notifications, and display preferences for this account.") {
            if isLoading {
                ProgressView("Loading preferences…")
            } else {
                SettingsCard(title: "Active hours", systemImage: "clock") {
                    TextField("Timezone", text: $timezone)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        TextField("Start · 08:00", text: $activeStart)
                        TextField("End · 22:00", text: $activeEnd)
                    }
                    Text("Use an IANA timezone and 24-hour HH:MM times. Blank values preserve the server default.")
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                }

                SettingsCard(title: "Delivery", systemImage: "bell") {
                    Toggle("Allow notifications", isOn: $notificationsEnabled)
                    Toggle("Allow task and briefing delivery", isOn: $deliveryEnabled)
                }

                SettingsCard(title: "Appearance", systemImage: "circle.lefthalf.filled") {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    Toggle("Reduce motion", isOn: $reduceMotion)
                }

                HStack {
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(message == "Saved" ? Theme.ok : .red)
                    }
                    Spacer()
                    Button("Save Changes") { Task { await save() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let loaded = try await APIClient(authManager: authManager).fetchUserAssistantSettings()
            settings = loaded
            timezone = loaded.timezone.value ?? TimeZone.current.identifier
            activeStart = loaded.activeHoursStart.value ?? ""
            activeEnd = loaded.activeHoursEnd.value ?? ""
            notificationsEnabled = loaded.notificationsEnabled.value ?? true
            deliveryEnabled = loaded.deliveryEnabled.value ?? true
            appearance = loaded.appearance.value ?? "system"
            reduceMotion = loaded.reduceMotion.value ?? false
        } catch {
            message = error.localizedDescription
        }
        isLoading = false
    }

    private func save() async {
        guard let settings else { return }
        isSaving = true
        message = nil
        defer { isSaving = false }
        do {
            let patch = UserAssistantSettingsPatch(
                expectedVersion: settings.version,
                timezone: timezone,
                activeHoursStart: activeStart.isEmpty ? nil : activeStart,
                activeHoursEnd: activeEnd.isEmpty ? nil : activeEnd,
                notificationsEnabled: notificationsEnabled,
                deliveryEnabled: deliveryEnabled,
                appearance: appearance,
                reduceMotion: reduceMotion
            )
            self.settings = try await APIClient(authManager: authManager)
                .updateUserAssistantSettings(patch)
            message = "Saved"
        } catch {
            message = error.localizedDescription
        }
    }
}

struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(Theme.textDim)
                }
                content
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Theme.bg)
        .navigationTitle(title)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            Divider().overlay(Theme.stroke)
            content
                .foregroundStyle(Theme.textMid)
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.strokeUp, lineWidth: 1))
    }
}

struct SettingsSourceLabel: View {
    let source: String

    var body: some View {
        Text("SOURCE · \(source.uppercased())")
            .font(Theme.mono(9, weight: .semibold))
            .foregroundStyle(Theme.textFaint)
    }
}

struct SettingsCapabilityChip: View {
    let label: String
    let enabled: Bool

    var body: some View {
        Text(label)
            .font(Theme.mono(9, weight: .semibold))
            .foregroundStyle(enabled ? Theme.ok : Theme.textFaint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background((enabled ? Theme.ok : Theme.textFaint).opacity(0.10), in: Capsule())
    }
}
