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

    @State private var showResult = false
    @State private var showDetail = false

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

            if task.canStop {
                stopButton
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
            TaskDetailSheet(task: task, onApprove: onApprove, onReject: onReject, onStop: onStop, onRun: onRun, onReset: onReset)
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

            if task.result != nil || task.isPendingApproval {
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
        Text(task.instruction)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
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

    @ViewBuilder
    private var resultRow: some View {
        if let result = task.result {
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
                .buttonStyle(.plain)

                if !showResult {
                    Text(String(result.prefix(80)) + (result.count > 80 ? "…" : ""))
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                if showResult {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(linkifiedAttributedString(result))
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
            }
        }
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

    private var stopButton: some View {
        Button(role: .destructive) {
            onStop?()
        } label: {
            Label("Stop Task", systemImage: "stop.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.top, 2)
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
}

// MARK: - Preview

#Preview("Completed") {
    List {
        TaskRow(task: TaskSummary(
            id: 1,
            title: "Morning Briefing",
            instruction: "Check my calendar and summarize anything urgent for today.",
            status: "completed",
            taskType: "recurring",
            schedule: "every:1d",
            deliver: true,
            requiresApproval: false,
            result: "You have 3 meetings today: standup at 9am, design review at 2pm, and a dentist appointment at 5pm. No urgent emails.",
            error: nil,
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
                status: "waiting_approval",
                taskType: "one_shot",
                schedule: nil,
                deliver: true,
                requiresApproval: true,
                result: nil,
                error: nil,
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
            status: "failed",
            taskType: "recurring",
            schedule: "every:12h",
            deliver: false,
            requiresApproval: false,
            result: nil,
            error: "LLM call failed: connection timeout after 30s",
            lastRunAt: Date(timeIntervalSinceNow: -3600),
            nextRunAt: Date(timeIntervalSinceNow: 1800),
            currentStepTitle: nil,
            waitingApprovalTool: nil
        ))
    }
}
