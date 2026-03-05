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

    @State private var audit: TaskAuditOut? = nil
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
                    // ── Result ────────────────────────────────────────────
                    if let result = audit.result {
                        Section("Result") {
                            Text(result)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
    }

    // MARK: - Tool call row

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
                Text(String(argsStr.prefix(150)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !entry.resultSummary.isEmpty {
                Text(String(entry.resultSummary.prefix(150)))
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
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
            audit = try await api.fetchTaskAudit(task.id)
        } catch {
            loadError = error.localizedDescription
        }
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
        nextRunAt: Calendar.current.date(byAdding: .day, value: 1, to: Date())
    ))
    .environment(AuthManager())
}
