//
//  TaskDetailSheet.swift
//  FruitcakeAi
//
//  Shows the full result and tool call timeline for a completed task.
//  Presented as a sheet from TaskRow.
//

import SwiftUI

private struct TaskDetailModelOption: Decodable, Identifiable, Hashable {
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

private struct TaskDetailModelListResponse: Decodable {
    let models: [TaskDetailModelOption]
}

struct TaskDetailSheet: View {

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    let task: TaskSummary
    var onApprove: (() -> Void)? = nil
    var onReject: (() -> Void)? = nil
    var onStop: (() -> Void)? = nil
    var onRun: (() -> Void)? = nil
    var onReset: (() -> Void)? = nil
    var onUpdated: (() -> Void)? = nil

    @State private var audit: TaskAuditOut? = nil
    @State private var steps: [TaskStepSummary] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var availableModels: [TaskDetailModelOption] = []
    @State private var selectedModelOverride = ""
    @State private var isSavingModel = false
    @State private var showEditor = false
    @State private var editedTask: TaskSummary? = nil
    @State private var exportPath = ""
    @State private var isExporting = false
    @State private var exportStatusMessage: String?

    private var currentTask: TaskSummary {
        editedTask ?? task
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(currentTask.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("Edit") { showEditor = true }
                    .buttonStyle(.bordered)
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let audit {
                List {
                    if currentTask.isPendingApproval {
                        Section("Approval Required") {
                            Text(currentTask.approvalContextLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            HStack(spacing: 10) {
                                Button {
                                    onApprove?()
                                    dismiss()
                                } label: {
                                    Label("Approve", systemImage: "checkmark")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)

                                Button(role: .destructive) {
                                    onReject?()
                                    dismiss()
                                } label: {
                                    Label("Reject", systemImage: "xmark")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    if currentTask.canStop || currentTask.canRun || currentTask.canReset {
                        Section("Actions") {
                            HStack(spacing: 10) {
                                if currentTask.canRun {
                                    Button {
                                        onRun?()
                                        dismiss()
                                    } label: {
                                        Label("Run", systemImage: "play.circle")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue)
                                }

                                if currentTask.canReset {
                                    Button {
                                        onReset?()
                                        dismiss()
                                    } label: {
                                        Label("Reset", systemImage: "arrow.counterclockwise.circle")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                }

                                if currentTask.canStop {
                                    Button(role: .destructive) {
                                        onStop?()
                                        dismiss()
                                    } label: {
                                        Label("Stop", systemImage: "stop.circle")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }

                    if currentTask.isAgentTask && (currentTask.hasRichResult || audit.result != nil) {
                        Section("Export Findings") {
                            TextField("Workspace path", text: $exportPath)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif

                            Button {
                                Task { await exportFindings() }
                            } label: {
                                if isExporting {
                                    Label("Exporting…", systemImage: "square.and.arrow.down")
                                } else {
                                    Label("Write to Workspace File", systemImage: "square.and.arrow.down")
                                }
                            }
                            .disabled(isExporting || exportPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            if let exportStatusMessage, !exportStatusMessage.isEmpty {
                                Text(exportStatusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !steps.isEmpty {
                        Section("Plan Steps") {
                            ForEach(steps) { step in
                                stepRow(step)
                            }
                        }
                    }

                    Section("Task Settings") {
                        if let family = currentTask.recipeFamilyLabel {
                            LabeledContent("Family", value: family)
                        }
                        if let agentRole = currentTask.agentRoleLabel {
                            LabeledContent("Agent Role", value: agentRole)
                        }
                        LabeledContent("Type", value: currentTask.taskType == "one_shot" ? "One time" : "Recurring")
                        if let schedule = currentTask.scheduleLabel {
                            LabeledContent("Schedule", value: schedule)
                        }
                        if let timezone = currentTask.effectiveTimezone, !timezone.isEmpty {
                            LabeledContent("Timezone", value: timezone)
                        }
                        if let start = currentTask.activeHoursStart,
                           let end = currentTask.activeHoursEnd,
                           let tz = currentTask.activeHoursTz,
                           !start.isEmpty, !end.isEmpty, !tz.isEmpty {
                            LabeledContent("Active Hours", value: "\(start) – \(end) (\(tz))")
                        }
                    }

                    if let assumptions = currentTask.taskRecipe?.assumptions, !assumptions.isEmpty {
                        Section("Recipe Assumptions") {
                            ForEach(assumptions, id: \.self) { assumption in
                                Text("• \(assumption)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("Model") {
                        Picker("LLM", selection: $selectedModelOverride) {
                            Text("Automatic").tag("")
                            ForEach(availableModels) { model in
                                Text("\(model.providerLabel) · \(model.displayLabel)").tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(isSavingModel)
                        .onChange(of: selectedModelOverride) { oldValue, newValue in
                            guard oldValue != newValue else { return }
                            Task { await saveModelOverride(newValue) }
                        }

                        if isSavingModel {
                            ProgressView("Saving model…")
                        }
                    }

                    // ── Result ────────────────────────────────────────────
                    resultSection(audit: audit)

                    // ── Tool calls ────────────────────────────────────────
                    if !audit.toolCalls.isEmpty {
                        Section("Tool Calls (\(audit.toolCalls.count))") {
                            ForEach(audit.toolCalls, id: \.id) { entry in
                                toolCallRow(entry)
                            }
                        }
                    }

                    if !currentTask.hasRichResult && audit.result == nil && audit.toolCalls.isEmpty {
                        Section {
                            Text("No execution data available yet.")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .task {
            selectedModelOverride = currentTask.llmModelOverride ?? ""
            if exportPath.isEmpty {
                exportPath = suggestedExportPath(for: currentTask)
            }
            await load()
            await loadModels()
        }
        .sheet(isPresented: $showEditor) {
            TaskCreateSheet(initialTask: currentTask, onSaved: { updated in
                editedTask = updated
                selectedModelOverride = updated.llmModelOverride ?? ""
                onUpdated?()
                Task { await load() }
            })
            .environment(authManager)
            #if os(iOS)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .frame(minWidth: 400, idealWidth: 500, minHeight: 400, idealHeight: 550)
    }

    // MARK: - Tool call row

    private func stepRow(_ step: TaskStepSummary) -> some View {
        let isCurrent = (currentTask.currentStepTitle == step.title) || (step.status == "running" || step.status == "waiting_approval")
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(step.stepIndex). \(step.title)")
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                Spacer()
                Text(step.status.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption2)
                    .foregroundStyle(isCurrent ? .orange : .secondary)
            }
            if let tool = step.waitingApprovalTool, !tool.isEmpty {
                Text("Tool: \(tool)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(isCurrent ? .orange.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private func toolCallRow(_ entry: TaskAuditEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.tool)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(entry.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !entry.arguments.isEmpty {
                let argsStr = entry.arguments.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                Text(String(argsStr.prefix(220)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if !entry.resultSummary.isEmpty {
                Text(String(entry.resultSummary.prefix(220)))
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let api = APIClient(authManager: authManager)
            async let taskData = api.fetchTask(currentTask.id)
            async let auditData = api.fetchTaskAudit(currentTask.id)
            async let stepData = api.fetchTaskSteps(currentTask.id)
            editedTask = try await taskData
            audit = try await auditData
            steps = (try? await stepData) ?? []
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadModels() async {
        do {
            let api = APIClient(authManager: authManager)
            let response: TaskDetailModelListResponse = try await api.request("/llm/models")
            availableModels = response.models
        } catch {
            if loadError == nil {
                loadError = error.localizedDescription
            }
        }
    }

    private func saveModelOverride(_ value: String) async {
        isSavingModel = true
        defer { isSavingModel = false }
        do {
            let api = APIClient(authManager: authManager)
            let updated = try await api.updateTaskModelOverride(currentTask.id, llmModelOverride: value.isEmpty ? nil : value)
            editedTask = updated
            onUpdated?()
        } catch {
            loadError = error.localizedDescription
            selectedModelOverride = currentTask.llmModelOverride ?? ""
        }
    }

    private func exportFindings() async {
        let path = exportPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        isExporting = true
        exportStatusMessage = nil
        defer { isExporting = false }
        do {
            let api = APIClient(authManager: authManager)
            let response = try await api.exportTaskResult(currentTask.id, path: path)
            exportPath = response.path
            exportStatusMessage = "Exported to \(response.path)"
        } catch {
            exportStatusMessage = error.localizedDescription
        }
    }

    private func suggestedExportPath(for task: TaskSummary) -> String {
        let slug = task.title
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let base = slug.isEmpty ? "agent_findings" : slug
        return "reports/\(base).md"
    }

    @ViewBuilder
    private func resultSection(audit: TaskAuditOut) -> some View {
        if let sections = currentTask.resultSections, !sections.isEmpty {
            Section("Result") {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                        VStack(alignment: .leading, spacing: 6) {
                            if !section.heading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(section.heading)
                                    .font(.headline)
                                    .foregroundStyle(section.isEmptyState ? .secondary : .primary)
                            }
                            sectionBodyView(section.body, isEmptyState: section.isEmptyState)
                        }
                        if index < sections.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(12)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        } else if let markdown = currentTask.resultMarkdown {
            Section("Result") {
                VStack(alignment: .leading, spacing: 0) {
                    Text(linkifiedAttributedString(markdown))
                        .font(.body)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .tint(.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        } else if let result = audit.result {
            Section("Result") {
                VStack(alignment: .leading, spacing: 0) {
                    Text(linkifiedAttributedString(result))
                        .font(.body)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .tint(.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private func sectionBodyView(_ text: String, isEmptyState: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(sectionBodyLines(text).enumerated()), id: \.offset) { _, line in
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Color.clear
                        .frame(height: 4)
                } else {
                    Text(linkifiedAttributedString(line))
                        .font(.body)
                        .lineSpacing(4)
                        .italic(isEmptyState)
                        .foregroundStyle(isEmptyState ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func sectionBodyLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
    }

    private func linkifiedAttributedString(_ text: String) -> AttributedString {
        MarkdownText.attributedString(from: text)
    }
}

// MARK: - Preview

#Preview {
    TaskDetailSheet(task: TaskSummary(
        id: 1,
        title: "Morning Briefing",
        instruction: "Check my calendar and summarize anything urgent.",
        persona: nil,
        profile: nil,
        llmModelOverride: nil,
        status: "completed",
        taskType: "recurring",
        schedule: "every:1d",
        deliver: true,
        requiresApproval: false,
        result: "You have 3 meetings today: standup at 9am, design review at 2pm, and dentist at 5pm.",
        error: nil,
        activeHoursStart: nil,
        activeHoursEnd: nil,
        activeHoursTz: nil,
        effectiveTimezone: nil,
        taskRecipe: nil,
        lastRunAt: Date(),
        nextRunAt: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
        currentStepTitle: nil,
        waitingApprovalTool: nil
    ))
    .environment(AuthManager())
}
