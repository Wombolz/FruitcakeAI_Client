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

    @State private var isSubmitting = false
    @State private var submitError: String?

    private let createScheduleOptions: [(key: String, label: String)] = [
        ("one_shot",   "One time"),
        ("every:30m",  "Every 30 min"),
        ("every:1h",   "Every hour"),
        ("every:6h",   "Every 6 hours"),
        ("every:12h",  "Every 12 hours"),
        ("every:1d",   "Daily"),
        ("custom",     "Custom cron…"),
    ]

    private let recurringScheduleOptions: [(key: String, label: String)] = [
        ("every:30m",  "Every 30 min"),
        ("every:1h",   "Every hour"),
        ("every:6h",   "Every 6 hours"),
        ("every:12h",  "Every 12 hours"),
        ("every:1d",   "Daily"),
        ("custom",     "Custom cron…"),
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

        let draftOrTaskTitle = initialDraft?.title ?? initialTask?.title ?? ""
        let draftOrTaskInstruction = initialDraft?.instruction ?? initialTask?.instruction ?? ""
        let draftOrTaskDeliver = initialDraft?.deliver ?? initialTask?.deliver ?? true
        let draftOrTaskApproval = initialDraft?.requiresApproval ?? initialTask?.requiresApproval ?? true
        let draftOrTaskStart = initialDraft?.activeHoursStart ?? initialTask?.activeHoursStart ?? "07:00"
        let draftOrTaskEnd = initialDraft?.activeHoursEnd ?? initialTask?.activeHoursEnd ?? "22:00"
        let draftOrTaskTz = initialDraft?.activeHoursTz ?? initialTask?.activeHoursTz
        let draftOrTaskModel = initialDraft?.llmModelOverride ?? initialTask?.llmModelOverride ?? ""
        let draftOrTaskFamily = initialDraft?.taskRecipe?.family ?? initialTask?.taskRecipe?.family ?? ""
        let draftOrTaskType = initialDraft?.taskType ?? initialTask?.taskType ?? "one_shot"
        let draftOrTaskSchedule = initialDraft?.schedule ?? initialTask?.schedule

        _title = State(initialValue: draftOrTaskTitle)
        _instruction = State(initialValue: draftOrTaskInstruction)
        _deliver = State(initialValue: draftOrTaskDeliver)
        _requiresApproval = State(initialValue: draftOrTaskApproval)
        _activeHoursStart = State(initialValue: draftOrTaskStart)
        _activeHoursEnd = State(initialValue: draftOrTaskEnd)
        _activeHoursEnabled = State(initialValue: draftOrTaskTz != nil && !draftOrTaskTz!.isEmpty)
        _selectedModelOverride = State(initialValue: draftOrTaskModel)
        _selectedRecipeFamily = State(initialValue: draftOrTaskFamily)

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
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSubmitting
    }

    private var availableScheduleOptions: [(key: String, label: String)] {
        createScheduleOptions
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
                if let initialDraft {
                    draftReviewSection(initialDraft)
                }
                taskFamilySection
                titleSection
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
        #if os(macOS)
        .frame(width: 480, height: 560)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #endif
    }

    private func draftReviewSection(_ draft: TaskDraft) -> some View {
        Section("Draft Review") {
            if let family = draft.taskRecipe?.family, !family.isEmpty {
                LabeledContent("Task Family", value: family.replacingOccurrences(of: "_", with: " ").capitalized)
            }
            if let confirmation = draft.taskConfirmation, !confirmation.isEmpty {
                Text(confirmation)
                    .font(.subheadline)
            }
            if let assumptions = draft.taskRecipe?.assumptions, !assumptions.isEmpty {
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

    private var instructionSection: some View {
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

    private var scheduleSection: some View {
        Section("Frequency") {
            Picker("Schedule", selection: $scheduleKey) {
                ForEach(availableScheduleOptions, id: \.key) { option in
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

    private func resolvedRecipeParams() -> [String: StringCodable]? {
        selectedRecipeFamily == sourceRecipeFamily ? sourceRecipeParams : nil
    }

    private func submit() async {
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
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
                let taskType: String
                switch scheduleKey {
                case "one_shot": taskType = "one_shot"
                default: taskType = "recurring"
                }
                let created = try await api.createTask(
                    CreateTaskRequest(
                        title: trimmedTitle,
                        instruction: trimmedInstruction,
                        llmModelOverride: selectedModelOverride.isEmpty ? nil : selectedModelOverride,
                        taskType: taskType,
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
                if taskType == "one_shot" && runNow {
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
