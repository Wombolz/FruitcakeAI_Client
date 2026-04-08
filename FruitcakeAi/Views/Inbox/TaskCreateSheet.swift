//
//  TaskCreateSheet.swift
//  FruitcakeAi
//
//  Modal form for creating a new task or editing an existing one.
//

import SwiftUI

private struct TaskModelOption: Decodable, Identifiable, Hashable {
    let id: String
    let provider: String
    let label: String
    let isDefaultChat: Bool
    let isDefaultTaskSmall: Bool
    let isDefaultTaskLarge: Bool

    var displayLabel: String {
        if isDefaultTaskSmall || isDefaultTaskLarge {
            return "\(label) (Default task)"
        }
        return label
    }

    var providerLabel: String {
        provider.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct TaskModelListResponse: Decodable {
    let models: [TaskModelOption]
}

struct TaskCreateSheet: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    let initialDraft: TaskDraft?
    let initialTask: TaskSummary?
    var onCreated: () -> Void = {}
    var onSaved: ((TaskSummary) -> Void)? = nil

    @State private var title = ""
    @State private var instruction = ""
    @State private var scheduleKey = "one_shot"
    @State private var customCron = ""
    @State private var deliver = true
    @State private var requiresApproval = true
    @State private var runNow = true
    @State private var activeHoursEnabled = false
    @State private var activeHoursStart = "07:00"
    @State private var activeHoursEnd = "22:00"
    @State private var availableModels: [TaskModelOption] = []
    @State private var selectedModelOverride = ""
    @State private var selectedRecipeFamily = ""
    @State private var briefingMode = "morning"
    @State private var briefingTopic = ""
    @State private var briefingPath = ""
    @State private var briefingWindowHours = "24"
    @State private var briefingMarketSymbol = "KO"
    @State private var briefingCustomGuidance = ""
    @State private var watcherTopic = ""
    @State private var watcherThreshold = "medium"
    @State private var watcherSources = ""

    @State private var isSubmitting = false
    @State private var submitError: String?

    private let createScheduleOptions: [(key: String, label: String)] = [
        ("one_shot", "One time"),
        ("every:30m", "Every 30 min"),
        ("every:1h", "Every hour"),
        ("every:6h", "Every 6 hours"),
        ("every:12h", "Every 12 hours"),
        ("every:1d", "Daily"),
        ("custom", "Custom cron…"),
    ]

    private let taskFamilyOptions: [(key: String, label: String)] = [
        ("", "Generic"),
        ("topic_watcher", "Watcher"),
        ("briefing", "Briefing"),
        ("iss_pass_watcher", "ISS Watcher"),
        ("weather_conditions", "Weather"),
        ("maintenance", "Maintenance")
    ]

    init(initialDraft: TaskDraft? = nil, initialTask: TaskSummary? = nil, onCreated: @escaping () -> Void = {}, onSaved: ((TaskSummary) -> Void)? = nil) {
        self.initialDraft = initialDraft
        self.initialTask = initialTask
        self.onCreated = onCreated
        self.onSaved = onSaved

        let recipe = initialDraft?.taskRecipe ?? initialTask?.taskRecipe
        let draftOrTaskTitle = initialDraft?.title ?? initialTask?.title ?? ""
        let draftOrTaskInstruction = initialDraft?.instruction ?? initialTask?.instruction ?? ""
        let draftOrTaskDeliver = initialDraft?.deliver ?? initialTask?.deliver ?? true
        let draftOrTaskApproval = initialDraft?.requiresApproval ?? initialTask?.requiresApproval ?? true
        let draftOrTaskStart = initialDraft?.activeHoursStart ?? initialTask?.activeHoursStart ?? "07:00"
        let draftOrTaskEnd = initialDraft?.activeHoursEnd ?? initialTask?.activeHoursEnd ?? "22:00"
        let draftOrTaskTz = initialDraft?.activeHoursTz ?? initialTask?.activeHoursTz
        let draftOrTaskModel = initialDraft?.llmModelOverride ?? initialTask?.llmModelOverride ?? ""
        let rawDraftOrTaskFamily = recipe?.family ?? ""
        let draftOrTaskFamily = Self.canonicalRecipeFamily(rawDraftOrTaskFamily)
        let draftOrTaskType = initialDraft?.taskType ?? initialTask?.taskType ?? "one_shot"
        let draftOrTaskSchedule = initialDraft?.schedule ?? initialTask?.schedule
        let briefingMode = Self.initialBriefingMode(
            family: rawDraftOrTaskFamily,
            recipe: recipe,
            title: draftOrTaskTitle,
            instruction: draftOrTaskInstruction
        )
        let briefingGuidance = recipe?.paramString("custom_guidance") ?? ""
        let watcherSourceText = recipe?.paramStringArray("sources").joined(separator: ", ") ?? ""

        _title = State(initialValue: draftOrTaskTitle)
        _instruction = State(initialValue: draftOrTaskFamily == "briefing" ? "" : draftOrTaskInstruction)
        _deliver = State(initialValue: draftOrTaskDeliver)
        _requiresApproval = State(initialValue: draftOrTaskApproval)
        _activeHoursStart = State(initialValue: draftOrTaskStart)
        _activeHoursEnd = State(initialValue: draftOrTaskEnd)
        _activeHoursEnabled = State(initialValue: !(draftOrTaskTz ?? "").isEmpty)
        _selectedModelOverride = State(initialValue: draftOrTaskModel)
        _selectedRecipeFamily = State(initialValue: draftOrTaskFamily)
        _briefingMode = State(initialValue: briefingMode)
        _briefingTopic = State(initialValue: recipe?.paramString("topic") ?? "")
        _briefingPath = State(initialValue: recipe?.paramString("path") ?? "")
        _briefingWindowHours = State(initialValue: String(recipe?.paramInt("window_hours") ?? 24))
        _briefingMarketSymbol = State(initialValue: recipe?.paramString("market_symbol") ?? "KO")
        _briefingCustomGuidance = State(initialValue: briefingGuidance)
        _watcherTopic = State(initialValue: recipe?.paramString("topic") ?? "")
        _watcherThreshold = State(initialValue: recipe?.paramString("threshold") ?? "medium")
        _watcherSources = State(initialValue: watcherSourceText)

        if draftOrTaskType == "one_shot" || draftOrTaskSchedule == nil {
            _scheduleKey = State(initialValue: "one_shot")
            _customCron = State(initialValue: "")
        } else if ["every:30m", "every:1h", "every:6h", "every:12h", "every:1d"].contains(draftOrTaskSchedule) {
            _scheduleKey = State(initialValue: draftOrTaskSchedule ?? "every:1d")
            _customCron = State(initialValue: "")
        } else {
            _scheduleKey = State(initialValue: "custom")
            _customCron = State(initialValue: draftOrTaskSchedule ?? "")
        }
    }

    private var isEditing: Bool { initialTask != nil }

    private var editorTitle: String {
        isEditing ? "Edit Task" : "New Task"
    }

    private var submitLabel: String {
        isEditing ? "Save" : "Create"
    }

    private static func canonicalRecipeFamily(_ family: String) -> String {
        switch family {
        case "daily_research_briefing", "morning_briefing":
            return "briefing"
        default:
            return family
        }
    }

    private static func initialBriefingMode(family: String, recipe: TaskRecipeMetadata?, title: String, instruction: String) -> String {
        if let mode = recipe?.paramString("briefing_mode")?.lowercased(), ["morning", "evening"].contains(mode) {
            return mode
        }
        if family == "morning_briefing" {
            return "morning"
        }
        let combined = "\(title)\n\(instruction)".lowercased()
        return combined.contains("evening") ? "evening" : "morning"
    }

    private var canSubmit: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if selectedRecipeFamily == "briefing" {
            return hasTitle && !isSubmitting
        }
        if selectedRecipeFamily == "topic_watcher" {
            return hasTitle
                && !watcherTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !isSubmitting
        }
        return hasTitle && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    private var sourceRecipeFamily: String? {
        Self.canonicalRecipeFamily(initialDraft?.taskRecipe?.family ?? initialTask?.taskRecipe?.family ?? "")
    }

    private var sourceRecipeParams: [String: StringCodable]? {
        initialDraft?.taskRecipe?.params ?? initialTask?.taskRecipe?.params
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text(editorTitle)
                    .font(.headline)
                Spacer()
                Button(submitLabel) {
                    Task { await submit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
                .overlay {
                    if isSubmitting {
                        ProgressView().controlSize(.mini)
                    }
                }
            }
            .padding()

            Divider()

            Form {
                recipeContextSection
                taskFamilySection
                titleSection
                familySpecificSection
                instructionSection
                scheduleSection
                modelSection
                optionsSection
                activeHoursSection
                if let error = submitError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .task { await loadModels() }
        .onChange(of: selectedRecipeFamily) { _, newValue in
            applyFamilyDefaults(for: newValue)
        }
        #if os(macOS)
        .frame(width: 520, height: 700)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #endif
    }

    @ViewBuilder
    private var recipeContextSection: some View {
        if let draft = initialDraft,
           hasRecipeContext(draft.taskRecipe, confirmation: draft.taskConfirmation) {
            recipeContextSection(recipe: draft.taskRecipe, confirmation: draft.taskConfirmation)
        } else if let recipe = initialTask?.taskRecipe,
                  hasRecipeContext(recipe, confirmation: nil) {
            recipeContextSection(recipe: recipe, confirmation: nil)
        }
    }

    private func hasRecipeContext(_ recipe: TaskRecipeMetadata?, confirmation: String?) -> Bool {
        let hasFamily = !((recipe?.family ?? "").isEmpty)
        let hasAssumptions = !(recipe?.assumptions ?? []).isEmpty
        let hasConfirmation = !((confirmation ?? "").isEmpty)
        return hasFamily || hasAssumptions || hasConfirmation
    }

    private func recipeContextSection(recipe: TaskRecipeMetadata?, confirmation: String?) -> some View {
        Section("Recipe Context") {
            if let family = recipe?.family, !family.isEmpty {
                LabeledContent("Recipe", value: family.replacingOccurrences(of: "_", with: " ").capitalized)
            }
            if let confirmation, !confirmation.isEmpty {
                Text(confirmation)
                    .font(.subheadline)
            }
            if let assumptions = recipe?.assumptions, !assumptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Assumptions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(assumptions, id: \.self) { assumption in
                        Text("• \(assumption)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var taskFamilySection: some View {
        Section("Task Type") {
            Picker("Type", selection: $selectedRecipeFamily) {
                ForEach(taskFamilyOptions, id: \.key) { option in
                    Text(option.label).tag(option.key)
                }
            }
            .pickerStyle(.menu)

            Text(taskFamilyHelperText(for: selectedRecipeFamily))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func taskFamilyHelperText(for family: String) -> String {
        switch family {
        case "topic_watcher":
            return "Use this for ongoing monitoring tasks that alert you when something meaningfully changes."
        case "briefing":
            return "Use this for a recurring morning or evening briefing with a stable structure and optional written output."
        case "iss_pass_watcher":
            return "Use this for recurring ISS visibility checks tied to a location."
        case "weather_conditions":
            return "Use this for recurring weather checks for a place or region."
        case "maintenance":
            return "Use this for bounded upkeep tasks like refresh, cleanup, or health checks."
        default:
            return "Use Generic when the task should stay freeform rather than following a built-in recipe."
        }
    }

    private var titleSection: some View {
        Section("Title") {
            TextField("e.g. Morning Briefing", text: $title)
                .autocorrectionDisabled()
        }
    }

    @ViewBuilder
    private var familySpecificSection: some View {
        if selectedRecipeFamily == "briefing" {
            Section {
                Picker("Mode", selection: $briefingMode) {
                    Text("Morning").tag("morning")
                    Text("Evening").tag("evening")
                }
                .pickerStyle(.menu)
                TextField("Topic", text: $briefingTopic)
                    .autocorrectionDisabled()
                TextField("Output path", text: $briefingPath)
                    .autocorrectionDisabled()
                TextField("Market symbol", text: $briefingMarketSymbol)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                HStack {
                    Text("Window (hours)")
                    Spacer()
                    TextField("24", text: $briefingWindowHours)
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                }
            } header: {
                Text("Briefing Details")
            } footer: {
                Text("Mode is required. Topic and output path enable a written research briefing; leave them blank for a profile-backed morning or evening briefing. Market symbol defaults to KO but can be changed.")
            }

            Section("Additional Guidance") {
                ZStack(alignment: .topLeading) {
                    if briefingCustomGuidance.isEmpty {
                        Text("Optional extra guidance for how the briefing should be written")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $briefingCustomGuidance)
                        .frame(minHeight: 90)
                }
            }
        } else if selectedRecipeFamily == "topic_watcher" {
            Section {
                TextField("Topic", text: $watcherTopic)
                    .autocorrectionDisabled()
                Picker("Threshold", selection: $watcherThreshold) {
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                }
                .pickerStyle(.menu)
                TextField("Suggested sources (comma-separated)", text: $watcherSources)
                    .autocorrectionDisabled()
            } header: {
                Text("Watcher Details")
            } footer: {
                Text("Watcher fields define the saved topic and threshold directly. Suggested sources are optional and will only stick if they match active RSS feeds.")
            }
        }
    }

    @ViewBuilder
    private var instructionSection: some View {
        if selectedRecipeFamily != "briefing" && selectedRecipeFamily != "topic_watcher" {
            Section {
                ZStack(alignment: .topLeading) {
                    if instruction.isEmpty {
                        Text("What should FruitcakeAI do?")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $instruction)
                        .frame(minHeight: 90)
                }
            } header: {
                Text("Instruction")
            }
        }
    }

    private var scheduleSection: some View {
        Section("Frequency") {
            Picker("Schedule", selection: $scheduleKey) {
                ForEach(createScheduleOptions, id: \.key) { option in
                    Text(option.label).tag(option.key)
                }
            }
            .pickerStyle(.menu)

            if scheduleKey == "custom" {
                TextField("e.g. 0 7 * * 1-5", text: $customCron)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
        }
    }

    private var optionsSection: some View {
        Section("Options") {
            Toggle("Push when done", isOn: $deliver)
            Toggle("Require approval before acting", isOn: $requiresApproval)
            if !isEditing && scheduleKey == "one_shot" {
                Toggle("Run immediately after create", isOn: $runNow)
            }
        }
    }

    private var modelSection: some View {
        Section {
            Picker("Model", selection: $selectedModelOverride) {
                Text("Automatic").tag("")
                ForEach(availableModels) { model in
                    Text("\(model.providerLabel) · \(model.displayLabel)").tag(model.id)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Model")
        } footer: {
            Text("Automatic uses the default task routing. Pick a model here to force one model for all LLM stages of this task.")
        }
    }

    private var activeHoursSection: some View {
        Section {
            Toggle("Restrict to active hours", isOn: $activeHoursEnabled)
            HStack {
                Text("From")
                Spacer()
                TextField("07:00", text: $activeHoursStart)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
            }
            .disabled(!activeHoursEnabled)
            .foregroundStyle(activeHoursEnabled ? .primary : .secondary)
            HStack {
                Text("Until")
                Spacer()
                TextField("22:00", text: $activeHoursEnd)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
            }
            .disabled(!activeHoursEnabled)
            .foregroundStyle(activeHoursEnabled ? .primary : .secondary)
        } header: {
            Text("Active Hours (\(TimeZone.current.abbreviation() ?? "Local"))")
        } footer: {
            Text("The task will only run during this window.")
        }
    }

    private func applyFamilyDefaults(for family: String) {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGuidance = briefingCustomGuidance.trimmingCharacters(in: .whitespacesAndNewlines)
        if family == "briefing" {
            if briefingWindowHours.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                briefingWindowHours = "24"
            }
            if briefingCustomGuidance.isEmpty && !trimmedInstruction.isEmpty {
                briefingCustomGuidance = trimmedInstruction
            }
        } else if family == "topic_watcher" {
            if watcherThreshold.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                watcherThreshold = "medium"
            }
            if watcherTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                watcherTopic = title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if instruction.isEmpty && !trimmedGuidance.isEmpty {
            instruction = trimmedGuidance
        }
    }

    private func resolvedSchedule() -> String? {
        switch scheduleKey {
        case "one_shot":
            return nil
        case "custom":
            let trimmed = customCron.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        default:
            return scheduleKey
        }
    }

    private func resolvedBriefingWindowHours() -> Int {
        let trimmed = briefingWindowHours.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(trimmed), value > 0 {
            return value
        }
        return 24
    }

    private func resolvedRecipeParams() -> [String: StringCodable]? {
        switch selectedRecipeFamily {
        case "":
            return nil
        case "briefing":
            let topic = briefingTopic.trimmingCharacters(in: .whitespacesAndNewlines)
            let pathValue = briefingPath.trimmingCharacters(in: .whitespacesAndNewlines)
            var params: [String: StringCodable] = [
                "briefing_mode": .string(briefingMode),
                "window_hours": .int(resolvedBriefingWindowHours()),
            ]
            let marketSymbol = briefingMarketSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !marketSymbol.isEmpty {
                params["market_symbol"] = .string(marketSymbol)
            }
            if !topic.isEmpty {
                params["topic"] = .string(topic)
            }
            if !pathValue.isEmpty {
                params["path"] = .string(pathValue)
            }
            let guidance = briefingCustomGuidance.trimmingCharacters(in: .whitespacesAndNewlines)
            if !guidance.isEmpty {
                params["custom_guidance"] = .string(guidance)
            }
            return params
        case "topic_watcher":
            let sourceValues = watcherSources
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var params: [String: StringCodable] = [
                "topic": .string(watcherTopic.trimmingCharacters(in: .whitespacesAndNewlines)),
                "threshold": .string(watcherThreshold.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
            ]
            if !sourceValues.isEmpty {
                params["sources"] = .array(sourceValues.map { .string($0) })
            }
            return params
        default:
            return selectedRecipeFamily == sourceRecipeFamily ? sourceRecipeParams : nil
        }
    }

    private func resolvedInstruction() -> String {
        if selectedRecipeFamily == "briefing" {
            let guidance = briefingCustomGuidance.trimmingCharacters(in: .whitespacesAndNewlines)
            return guidance.isEmpty ? "Prepare a \(briefingMode) briefing." : guidance
        }
        if selectedRecipeFamily == "topic_watcher" {
            return "Watch for significant updates about \(watcherTopic.trimmingCharacters(in: .whitespacesAndNewlines))."
        }
        return instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() async {
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstruction = resolvedInstruction()
        let tz = TimeZone.current.identifier
        let activeStart = activeHoursEnabled ? activeHoursStart : nil
        let activeEnd = activeHoursEnabled ? activeHoursEnd : nil
        let resolvedTaskType = (scheduleKey == "one_shot") ? "one_shot" : "recurring"
        let existingTaskTz = initialDraft?.activeHoursTz ?? initialTask?.activeHoursTz
        let activeTz = activeHoursEnabled ? tz : ((resolvedTaskType == "recurring") ? (existingTaskTz ?? tz) : nil)
        let recipeFamily = selectedRecipeFamily
        let recipeParams = resolvedRecipeParams()

        do {
            let api = APIClient(authManager: authManager)
            if let initialTask {
                let updated = try await api.updateTask(
                    initialTask.id,
                    TaskUpdateRequest(
                        title: trimmedTitle,
                        instruction: trimmedInstruction,
                        taskType: resolvedTaskType,
                        llmModelOverride: selectedModelOverride.isEmpty ? nil : selectedModelOverride,
                        schedule: resolvedSchedule(),
                        deliver: deliver,
                        requiresApproval: requiresApproval,
                        activeHoursStart: activeStart,
                        activeHoursEnd: activeEnd,
                        activeHoursTz: activeTz,
                        recipeFamily: recipeFamily,
                        recipeParams: recipeParams
                    )
                )
                onSaved?(updated)
            } else {
                let created = try await api.createTask(
                    CreateTaskRequest(
                        title: trimmedTitle,
                        instruction: trimmedInstruction,
                        llmModelOverride: selectedModelOverride.isEmpty ? nil : selectedModelOverride,
                        taskType: resolvedTaskType,
                        schedule: resolvedSchedule(),
                        deliver: deliver,
                        requiresApproval: requiresApproval,
                        activeHoursStart: activeStart,
                        activeHoursEnd: activeEnd,
                        activeHoursTz: activeTz,
                        recipeFamily: recipeFamily,
                        recipeParams: recipeParams
                    )
                )
                if resolvedTaskType == "one_shot" && runNow {
                    try await api.runTask(created.id)
                }
                onCreated()
            }
            dismiss()
        } catch {
            submitError = error.localizedDescription
        }
    }

    private func loadModels() async {
        do {
            let api = APIClient(authManager: authManager)
            let response: TaskModelListResponse = try await api.request("/llm/models")
            availableModels = response.models
        } catch {
            submitError = error.localizedDescription
        }
    }
}

#Preview {
    TaskCreateSheet()
        .environment(AuthManager())
}
