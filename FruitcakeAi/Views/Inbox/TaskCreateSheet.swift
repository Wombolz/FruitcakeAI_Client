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
    @State private var briefingTopic = ""
    @State private var briefingPath = ""
    @State private var briefingWindowHours = "24"
    @State private var briefingCustomGuidance = ""

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
        ("daily_research_briefing", "Daily Briefing"),
        ("morning_briefing", "Morning Briefing"),
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
        let draftOrTaskFamily = recipe?.family ?? ""
        let draftOrTaskType = initialDraft?.taskType ?? initialTask?.taskType ?? "one_shot"
        let draftOrTaskSchedule = initialDraft?.schedule ?? initialTask?.schedule
        let briefingGuidance = recipe?.paramString("custom_guidance") ?? ""

        _title = State(initialValue: draftOrTaskTitle)
        _instruction = State(initialValue: draftOrTaskFamily == "daily_research_briefing" ? "" : draftOrTaskInstruction)
        _deliver = State(initialValue: draftOrTaskDeliver)
        _requiresApproval = State(initialValue: draftOrTaskApproval)
        _activeHoursStart = State(initialValue: draftOrTaskStart)
        _activeHoursEnd = State(initialValue: draftOrTaskEnd)
        _activeHoursEnabled = State(initialValue: !(draftOrTaskTz ?? "").isEmpty)
        _selectedModelOverride = State(initialValue: draftOrTaskModel)
        _selectedRecipeFamily = State(initialValue: draftOrTaskFamily)
        _briefingTopic = State(initialValue: recipe?.paramString("topic") ?? "")
        _briefingPath = State(initialValue: recipe?.paramString("path") ?? "")
        _briefingWindowHours = State(initialValue: String(recipe?.paramInt("window_hours") ?? 24))
        _briefingCustomGuidance = State(initialValue: briefingGuidance)

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

    private var canSubmit: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if selectedRecipeFamily == "daily_research_briefing" {
            return hasTitle
                && !briefingTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !briefingPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !isSubmitting
        }
        return hasTitle && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    private var sourceRecipeFamily: String? {
        initialDraft?.taskRecipe?.family ?? initialTask?.taskRecipe?.family
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
        case "daily_research_briefing":
            return "Use this for scheduled summaries or briefings that gather and write up recent developments."
        case "morning_briefing":
            return "Use this for a recurring start-of-day briefing with a stable agenda."
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
        if selectedRecipeFamily == "daily_research_briefing" {
            Section {
                TextField("Topic", text: $briefingTopic)
                    .autocorrectionDisabled()
                TextField("Output path", text: $briefingPath)
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
                Text("These fields drive the briefing recipe directly, so the task can be repaired or saved without relying on instruction parsing.")
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
        }
    }

    @ViewBuilder
    private var instructionSection: some View {
        if selectedRecipeFamily != "daily_research_briefing" {
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
        if family == "daily_research_briefing" {
            if briefingWindowHours.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                briefingWindowHours = "24"
            }
            if briefingCustomGuidance.isEmpty && !trimmedInstruction.isEmpty {
                briefingCustomGuidance = trimmedInstruction
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
        case "daily_research_briefing":
            var params: [String: StringCodable] = [
                "topic": .string(briefingTopic.trimmingCharacters(in: .whitespacesAndNewlines)),
                "path": .string(briefingPath.trimmingCharacters(in: .whitespacesAndNewlines)),
                "window_hours": .int(resolvedBriefingWindowHours()),
            ]
            let guidance = briefingCustomGuidance.trimmingCharacters(in: .whitespacesAndNewlines)
            if !guidance.isEmpty {
                params["custom_guidance"] = .string(guidance)
            }
            return params
        default:
            return selectedRecipeFamily == sourceRecipeFamily ? sourceRecipeParams : nil
        }
    }

    private func resolvedInstruction() -> String {
        if selectedRecipeFamily == "daily_research_briefing" {
            let guidance = briefingCustomGuidance.trimmingCharacters(in: .whitespacesAndNewlines)
            return guidance.isEmpty ? "Prepare a daily research briefing." : guidance
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
        let activeTz = activeHoursEnabled ? tz : nil
        let recipeFamily = selectedRecipeFamily
        let recipeParams = resolvedRecipeParams()
        let resolvedTaskType = (scheduleKey == "one_shot") ? "one_shot" : "recurring"

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
