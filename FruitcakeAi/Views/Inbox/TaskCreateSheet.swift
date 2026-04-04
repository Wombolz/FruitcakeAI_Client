//
//  TaskCreateSheet.swift
//  FruitcakeAi
//
//  Modal form for creating a new task. Presented as a sheet from InboxView.
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
    var onCreated: () -> Void = {}

    // MARK: - Form state

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

    // MARK: - Submission state

    @State private var isSubmitting = false
    @State private var submitError: String?

    init(initialDraft: TaskDraft? = nil, onCreated: @escaping () -> Void = {}) {
        self.initialDraft = initialDraft
        self.onCreated = onCreated
        _title = State(initialValue: initialDraft?.title ?? "")
        _instruction = State(initialValue: initialDraft?.instruction ?? "")
        _deliver = State(initialValue: initialDraft?.deliver ?? true)
        _requiresApproval = State(initialValue: initialDraft?.requiresApproval ?? true)
        _activeHoursStart = State(initialValue: initialDraft?.activeHoursStart ?? "07:00")
        _activeHoursEnd = State(initialValue: initialDraft?.activeHoursEnd ?? "22:00")
        _activeHoursEnabled = State(initialValue: initialDraft?.activeHoursStart != nil && initialDraft?.activeHoursEnd != nil)
        _selectedModelOverride = State(initialValue: initialDraft?.llmModelOverride ?? "")
        _selectedRecipeFamily = State(initialValue: initialDraft?.taskRecipe?.family ?? "")

        let scheduleValue = initialDraft?.schedule
        if initialDraft?.taskType == "one_shot" || scheduleValue == nil {
            _scheduleKey = State(initialValue: "one_shot")
            _customCron = State(initialValue: "")
        } else if ["every:30m", "every:1h", "every:6h", "every:12h", "every:1d"].contains(scheduleValue) {
            _scheduleKey = State(initialValue: scheduleValue ?? "one_shot")
            _customCron = State(initialValue: "")
        } else {
            _scheduleKey = State(initialValue: "custom")
            _customCron = State(initialValue: scheduleValue ?? "")
        }
    }

    // MARK: - Schedule options

    private let scheduleOptions: [(key: String, label: String)] = [
        ("one_shot",   "One time"),
        ("every:30m",  "Every 30 min"),
        ("every:1h",   "Every hour"),
        ("every:6h",   "Every 6 hours"),
        ("every:12h",  "Every 12 hours"),
        ("every:1d",   "Daily"),
        ("custom",     "Custom cron…"),
    ]

    // MARK: - Validation

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !instruction.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isSubmitting
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("New Task")
                    .font(.headline)
                Spacer()
                Button("Create") {
                    Task { await submit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
                .overlay {
                    if isSubmitting {
                        ProgressView().controlSize(.mini)
                    }
                }
            }
            .padding()

            Divider()

            // Scrollable form content
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
        .frame(width: 480, height: 520)
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


    private let taskFamilyOptions: [(key: String, label: String)] = [
        ("", "Generic"),
        ("topic_watcher", "Watcher"),
        ("daily_research_briefing", "Daily Briefing"),
        ("morning_briefing", "Morning Briefing"),
        ("iss_pass_watcher", "ISS Watcher"),
        ("weather_conditions", "Weather"),
        ("maintenance", "Maintenance")
    ]

    private var taskFamilySection: some View {
        Section("Task Type") {
            Picker("Type", selection: $selectedRecipeFamily) {
                ForEach(taskFamilyOptions, id: \.key) { option in
                    Text(option.label).tag(option.key)
                }
            }
            .pickerStyle(.menu)

            if !selectedRecipeFamily.isEmpty {
                Text(taskFamilyHelperText(for: selectedRecipeFamily))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
            return "Use Generic when the task does not fit a known task family yet."
        }
    }

    // MARK: - Sections

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
                    .frame(minHeight: 80)
            }
        } header: {
            Text("Instruction")
        }
    }

    private var scheduleSection: some View {
        Section("Frequency") {
            Picker("Schedule", selection: $scheduleKey) {
                ForEach(scheduleOptions, id: \.key) { option in
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
            if scheduleKey == "one_shot" {
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

    // MARK: - Submit

    private func submit() async {
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        let taskType: String
        let schedule: String?

        switch scheduleKey {
        case "one_shot":
            taskType = "one_shot"
            schedule = nil
        case "custom":
            taskType = "recurring"
            schedule = customCron.trimmingCharacters(in: .whitespaces).isEmpty ? nil : customCron
        default:
            taskType = "recurring"
            schedule = scheduleKey
        }

        let tz = TimeZone.current.identifier
        let req = CreateTaskRequest(
            title: title.trimmingCharacters(in: .whitespaces),
            instruction: instruction.trimmingCharacters(in: .whitespaces),
            llmModelOverride: selectedModelOverride.isEmpty ? nil : selectedModelOverride,
            taskType: taskType,
            schedule: schedule,
            deliver: deliver,
            requiresApproval: requiresApproval,
            activeHoursStart: activeHoursEnabled ? activeHoursStart : nil,
            activeHoursEnd:   activeHoursEnabled ? activeHoursEnd   : nil,
            activeHoursTz:    activeHoursEnabled ? tz               : nil,
            recipeFamily: selectedRecipeFamily.isEmpty ? nil : selectedRecipeFamily,
            recipeParams: selectedRecipeFamily == initialDraft?.taskRecipe?.family ? initialDraft?.taskRecipe?.params : nil
        )

        do {
            let api = APIClient(authManager: authManager)
            let created = try await api.createTask(req)
            if taskType == "one_shot" && runNow {
                try await api.runTask(created.id)
            }
            onCreated()
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

// MARK: - Preview

#Preview {
    TaskCreateSheet()
        .environment(AuthManager())
}
