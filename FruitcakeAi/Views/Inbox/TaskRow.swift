//
//  TaskRow.swift
//  FruitcakeAi
//
//  A single row in InboxView showing task status, result, and action buttons.
//  No network dependency — preview-testable with static data.
//

import SwiftUI

struct TaskRow: View {

    @Environment(AuthManager.self) private var authManager

    let task: TaskSummary
    var onApprove:     (() -> Void)? = nil
    var onReject:      (() -> Void)? = nil
    var onStop:        (() -> Void)? = nil
    var onRun:         (() -> Void)? = nil
    var onReset:       (() -> Void)? = nil
    var onDelete:      (() -> Void)? = nil
    var onReplyInChat: (() -> Void)? = nil
    var onUpdated:     (() -> Void)? = nil

    @State private var showResult = false
    @State private var showDetail = false
    @State private var isExporting = false
    @State private var exportStatusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            instructionPreview

            if task.result != nil {
                resultRow
            }

            if let error = task.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if task.isPendingApproval {
                approvalCallout
                approvalButtons
            }

            actionButtons

            if let exportStatusMessage, !exportStatusMessage.isEmpty {
                Text(exportStatusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if task.result != nil {
                replyButton
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete?()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showDetail) {
            TaskDetailSheet(task: task, onApprove: onApprove, onReject: onReject, onStop: onStop, onRun: onRun, onReset: onReset, onUpdated: onUpdated)
                .environment(authManager)
        }
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            statusBadge

            Text(task.title)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            if let next = task.nextRunAt {
                Text(next.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if task.result != nil || task.isPendingApproval || task.canRun || task.canStop || task.canReset {
                Button { showDetail = true } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .imageScale(.small)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            if task.isRunning {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(task.statusColor)
                    .frame(width: 8, height: 8)
            }
            Text(task.statusLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(task.statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(task.statusColor.opacity(0.12), in: Capsule())
    }

    private var instructionPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let family = task.recipeFamilyLabel {
                    metadataBadge(family, tint: .blue)
                }
                if let agentRole = task.agentRoleLabel {
                    metadataBadge(agentRole, tint: .orange)
                }
                if let schedule = task.scheduleLabel {
                    metadataBadge(schedule, tint: .secondary)
                }
            }

            Text(task.instruction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func metadataBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private var approvalCallout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.approvalContextLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            if let tool = task.waitingApprovalTool, !tool.isEmpty {
                Text("Tool: \(tool)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button("Review Details") {
                showDetail = true
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(8)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 4)
    }

    private var hasAnyResult: Bool {
        task.hasRichResult || task.result != nil
    }

    private var collapsedPreview: String {
        if let sections = task.resultSections, !sections.isEmpty {
            let headings = sections
                .map(\.heading)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " · ")
            if headings.isEmpty {
                let fallback = sections
                    .map(\.body)
                    .joined(separator: "\n")
                let truncated = String(fallback.prefix(80))
                return fallback.count > 80 ? truncated + "…" : truncated
            }
            let truncated = String(headings.prefix(80))
            return headings.count > 80 ? truncated + "…" : truncated
        }
        let text = task.resultMarkdown ?? task.result ?? ""
        let truncated = String(text.prefix(80))
        return text.count > 80 ? truncated + "…" : truncated
    }

    @ViewBuilder
    private var resultRow: some View {
        if hasAnyResult {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showResult.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showResult ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 12)

                        Text(showResult ? "Hide result" : "Show result")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                }
                .buttonStyle(.borderless)

                if !showResult {
                    Text(collapsedPreview)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                if showResult {
                    expandedResult
                }
            }
        }
    }

    @ViewBuilder
    private var expandedResult: some View {
        if let sections = task.resultSections, !sections.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                        VStack(alignment: .leading, spacing: 4) {
                            if !section.heading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(section.heading)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(section.isEmptyState ? .secondary : .primary)
                            }
                            sectionBodyView(section.body, isEmptyState: section.isEmptyState)
                        }
                        if index < sections.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: 400)
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        } else if let markdown = task.resultMarkdown {
            flatResultScroll(text: markdown)
        } else if let result = task.result {
            flatResultScroll(text: result)
        }
    }

    private func flatResultScroll(text: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(linkifiedAttributedString(text))
                    .font(.callout)
                    .lineSpacing(4)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .tint(.accentColor)
            }
        }
        .frame(maxHeight: 200)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
                        .font(.caption)
                        .lineSpacing(3)
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

    private var replyButton: some View {
        Button {
            onReplyInChat?()
        } label: {
            Label("Reply in Chat", systemImage: "bubble.left.and.text.bubble.right")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if task.canRun || task.canReset || task.canStop || (task.isAgentTask && hasAnyResult) {
            HStack(spacing: 12) {
                if task.canRun {
                    Button {
                        onRun?()
                    } label: {
                        Label("Run", systemImage: "play.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.small)
                }

                if task.canReset {
                    Button {
                        onReset?()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if task.canStop {
                    Button(role: .destructive) {
                        onStop?()
                    } label: {
                        Label(task.isRunning ? "Stop Task" : "Stop", systemImage: "stop.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if task.isAgentTask && hasAnyResult {
                    Button {
                        Task { await exportFindings() }
                    } label: {
                        Label(isExporting ? "Exporting…" : "Export", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isExporting)
                }
            }
            .padding(.top, 2)
        }
    }

    private var approvalButtons: some View {
        HStack(spacing: 12) {
            Button {
                onApprove?()
            } label: {
                Label("Approve", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.small)

            Button(role: .destructive) {
                onReject?()
            } label: {
                Label("Reject", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.top, 2)
    }

    private func linkifiedAttributedString(_ text: String) -> AttributedString {
        MarkdownText.attributedString(from: text)
    }

    private func exportFindings() async {
        isExporting = true
        exportStatusMessage = nil
        defer { isExporting = false }
        do {
            let api = APIClient(authManager: authManager)
            let response = try await api.exportTaskResult(task.id, path: suggestedExportPath())
            exportStatusMessage = "Exported to \(response.path)"
        } catch {
            exportStatusMessage = error.localizedDescription
        }
    }

    private func suggestedExportPath() -> String {
        let slug = task.title
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let base = slug.isEmpty ? "agent_findings" : slug
        return "reports/\(base).md"
    }
}

// MARK: - Preview

#Preview("Completed") {
    List {
        TaskRow(task: TaskSummary(
            id: 1,
            title: "Morning Briefing",
            instruction: "Check my calendar and summarize anything urgent for today.",
            persona: nil,
            profile: nil,
            llmModelOverride: nil,
            status: "completed",
            taskType: "recurring",
            schedule: "every:1d",
            deliver: true,
            requiresApproval: false,
            result: "You have 3 meetings today: standup at 9am, design review at 2pm, and a dentist appointment at 5pm. No urgent emails.",
            error: nil,
            activeHoursStart: nil,
            activeHoursEnd: nil,
            activeHoursTz: nil,
            effectiveTimezone: nil,
            taskRecipe: nil,
            lastRunAt: Date(),
            nextRunAt: Calendar.current.date(byAdding: .day, value: 1, to: Date())
            ,
            currentStepTitle: nil,
            waitingApprovalTool: nil
        ))
    }
}

#Preview("Needs Approval") {
    List {
        TaskRow(
            task: TaskSummary(
                id: 2,
                title: "Schedule Appointment",
                instruction: "Create a calendar event for the team lunch next Friday at noon.",
                persona: nil,
                profile: nil,
                llmModelOverride: nil,
                status: "waiting_approval",
                taskType: "one_shot",
                schedule: nil,
                deliver: true,
                requiresApproval: true,
                result: nil,
                error: nil,
                activeHoursStart: nil,
                activeHoursEnd: nil,
                activeHoursTz: nil,
                effectiveTimezone: nil,
                taskRecipe: nil,
                lastRunAt: nil,
                nextRunAt: nil,
                currentStepTitle: "Create calendar event",
                waitingApprovalTool: "create_event"
            ),
            onApprove: { print("Approved") },
            onReject:  { print("Rejected") }
        )
    }
}

#Preview("Failed") {
    List {
        TaskRow(task: TaskSummary(
            id: 3,
            title: "Weather Check",
            instruction: "Fetch the weather forecast for this week.",
            persona: nil,
            profile: nil,
            llmModelOverride: nil,
            status: "failed",
            taskType: "recurring",
            schedule: "every:12h",
            deliver: false,
            requiresApproval: false,
            result: nil,
            error: "LLM call failed: connection timeout after 30s",
            activeHoursStart: nil,
            activeHoursEnd: nil,
            activeHoursTz: nil,
            effectiveTimezone: nil,
            taskRecipe: nil,
            lastRunAt: Date(timeIntervalSinceNow: -3600),
            nextRunAt: Date(timeIntervalSinceNow: 1800),
            currentStepTitle: nil,
            waitingApprovalTool: nil
        ))
    }
}
