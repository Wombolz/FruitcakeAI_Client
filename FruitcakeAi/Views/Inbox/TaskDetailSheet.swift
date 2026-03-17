//
//  TaskDetailSheet.swift
//  FruitcakeAi
//
//  Shows the full result and tool call timeline for a completed task.
//  Presented as a sheet from TaskRow.
//

import SwiftUI

struct TaskDetailSheet: View {

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    let task: TaskSummary
    var onApprove: (() -> Void)? = nil
    var onReject: (() -> Void)? = nil
    var onStop: (() -> Void)? = nil
    var onRun: (() -> Void)? = nil
    var onReset: (() -> Void)? = nil

    @State private var audit: TaskAuditOut? = nil
    @State private var steps: [TaskStepSummary] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
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
                    if task.isPendingApproval {
                        Section("Approval Required") {
                            Text(task.approvalContextLabel)
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

                    if task.canStop || task.canRun || task.canReset {
                        Section("Actions") {
                            HStack(spacing: 10) {
                                if task.canRun {
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

                                if task.canReset {
                                    Button {
                                        onReset?()
                                        dismiss()
                                    } label: {
                                        Label("Reset", systemImage: "arrow.counterclockwise.circle")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                }

                                if task.canStop {
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

                    if !steps.isEmpty {
                        Section("Plan Steps") {
                            ForEach(steps) { step in
                                stepRow(step)
                            }
                        }
                    }

                    // ── Result ────────────────────────────────────────────
                    if let result = audit.result {
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

                    // ── Tool calls ────────────────────────────────────────
                    if !audit.toolCalls.isEmpty {
                        Section("Tool Calls (\(audit.toolCalls.count))") {
                            ForEach(audit.toolCalls, id: \.id) { entry in
                                toolCallRow(entry)
                            }
                        }
                    }

                    if audit.result == nil && audit.toolCalls.isEmpty {
                        Section {
                            Text("No execution data available yet.")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .task { await load() }
        .frame(minWidth: 400, idealWidth: 500, minHeight: 400, idealHeight: 550)
    }

    // MARK: - Tool call row

    private func stepRow(_ step: TaskStepSummary) -> some View {
        let isCurrent = (task.currentStepTitle == step.title) || (step.status == "running" || step.status == "waiting_approval")
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
            async let auditData = api.fetchTaskAudit(task.id)
            async let stepData = api.fetchTaskSteps(task.id)
            audit = try await auditData
            steps = (try? await stepData) ?? []
        } catch {
            loadError = error.localizedDescription
        }
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
        status: "completed",
        taskType: "recurring",
        schedule: "every:1d",
        deliver: true,
        requiresApproval: false,
        result: "You have 3 meetings today: standup at 9am, design review at 2pm, and dentist at 5pm.",
        error: nil,
        lastRunAt: Date(),
        nextRunAt: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
        currentStepTitle: nil,
        waitingApprovalTool: nil
    ))
    .environment(AuthManager())
}
