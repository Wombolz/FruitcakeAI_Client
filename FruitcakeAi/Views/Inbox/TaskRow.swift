//
//  TaskRow.swift
//  FruitcakeAi
//
//  A single task as a collapsible three-zone console card: header (status,
//  identity, next-run, kebab menu), body (description/result, or an inline
//  rename/schedule editor), footer (run/stop/export/reply actions).
//

import SwiftUI

private enum TaskRowEditMode: Equatable {
    case none
    case rename
    case schedule
}

private let taskCadenceOptions: [(key: String, label: String)] = [
    ("every:30m", "Every 30 min"),
    ("every:1h", "Every hour"),
    ("every:6h", "Every 6 hours"),
    ("every:12h", "Every 12 hours"),
    ("every:1d", "Daily"),
]

struct StatusDot: View {
    let status: String
    var color: Color = .gray

    @State private var pulse = false

    private var isRunning: Bool { status == "running" }
    private var isPending: Bool { status == "pending" || status == "waiting_approval" }
    private var dotColor: Color {
        isPending ? Theme.onDevice : color
    }

    var body: some View {
        ZStack {
            if isRunning {
                Circle()
                    .stroke(dotColor, lineWidth: 1.5)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 2.4 : 1)
                    .opacity(pulse ? 0 : 0.6)
                    .animation(.easeOut(duration: 1.3).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
        }
        .frame(width: 16, height: 16)
        .onAppear { pulse = true }
    }
}

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

    @State private var collapsed = false
    @State private var editing: TaskRowEditMode = .none
    @State private var showResult = false
    @State private var showDetail = false
    @State private var showKebabMenu = false
    @State private var isExporting = false
    @State private var exportStatusMessage: String?

    @State private var localAccentOverride: String?
    @State private var draftTitle = ""
    @State private var draftTaskType = "recurring"
    @State private var draftSchedule = "every:1d"
    @State private var isSavingEdit = false
    @State private var editError: String?

    private var accent: Color {
        if let localAccentOverride, let color = Color(taskAccentHex: localAccentOverride) {
            return color
        }
        return task.accent
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !collapsed {
                body_
                if editing == .none {
                    footer
                }
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke, lineWidth: 1))
        .overlay(alignment: .leading) {
            Rectangle().fill(accent).frame(width: 3)
        }
        .padding(.vertical, 4)
        .onAppear { localAccentOverride = TaskAccentStore.shared.accentHex(for: task.id) }
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

    // MARK: - Header

    private var header: some View {
        Button {
            guard editing == .none else { return }
            withAnimation(.easeInOut(duration: 0.18)) { collapsed.toggle() }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))

                StatusDot(status: task.status, color: task.statusColor)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 9) {
                        Text(task.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        statusBadge
                    }
                    HStack(spacing: 7) {
                        if let agentRole = task.agentRoleLabel {
                            Text("Agent · \(agentRole)")
                                .font(Theme.mono(10.5))
                                .foregroundStyle(accent)
                            Circle().fill(Theme.textFaint).frame(width: 3, height: 3)
                        }
                        Text(task.scheduleLabel ?? "Manual")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.textDim)
                    }
                }

                Spacer(minLength: 8)

                if let next = task.nextRunAt {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(next.formatted(.relative(presentation: .named)))
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.textMid)
                        Text("NEXT RUN")
                            .font(Theme.mono(9.5, weight: .semibold))
                            .kerning(0.6)
                            .foregroundStyle(Theme.textFaint)
                    }
                }

                kebabButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(editing != .none)
        .background(accent.opacity(0.08))
        .overlay(alignment: .bottom) {
            if !collapsed {
                Rectangle().fill(Theme.stroke).frame(height: 1)
            }
        }
    }

    private var statusBadge: some View {
        Text(task.statusLabel)
            .font(Theme.mono(10, weight: .medium))
            .foregroundStyle(task.statusColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(task.statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Kebab menu

    private var kebabButton: some View {
        Button {
            showKebabMenu = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textDim)
                .rotationEffect(.degrees(90))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showKebabMenu, arrowEdge: .top) {
            kebabMenuContent
        }
    }

    private var kebabMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("COLOR")
                .font(Theme.mono(9.5, weight: .semibold))
                .kerning(1.0)
                .foregroundStyle(Theme.textFaint)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

            HStack(spacing: 8) {
                ForEach(Array(PersonaAccent.palette.enumerated()), id: \.offset) { _, swatch in
                    colorSwatch(swatch)
                }
                hueWheelSwatch
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Divider()

            kebabRow("Rename", systemImage: "pencil") {
                startRename()
            }
            kebabRow("Edit schedule", systemImage: "clock") {
                startScheduleEdit()
            }

            Divider()

            kebabRow("Delete task", systemImage: "trash", role: .destructive) {
                showKebabMenu = false
                onDelete?()
            }
            .padding(.bottom, 6)
        }
        .frame(width: 230)
        .background(Theme.card)
    }

    private func colorSwatch(_ color: Color) -> some View {
        let hex = color.taskAccentHexString()
        let isActive = localAccentOverride?.uppercased() == hex.uppercased()
        return Button {
            setAccent(hex)
        } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? Theme.text : .clear, lineWidth: 2)
                        .padding(-2)
                )
        }
        .buttonStyle(.plain)
    }

    private var hueWheelSwatch: some View {
        let isCustom = localAccentOverride != nil && !PersonaAccent.palette.contains { $0.taskAccentHexString().uppercased() == localAccentOverride?.uppercased() }
        return ZStack {
            AngularGradient(
                colors: [
                    Color(hex: 0xFF4D4D), Color(hex: 0xFFD24D), Color(hex: 0x4DFF88),
                    Color(hex: 0x4DD2FF), Color(hex: 0x4D4DFF), Color(hex: 0xFF4DF0), Color(hex: 0xFF4D4D)
                ],
                center: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            ColorPicker("", selection: Binding(
                get: { accent },
                set: { setAccent($0.taskAccentHexString()) }
            ), supportsOpacity: false)
            .labelsHidden()
            .opacity(0.02)
        }
        .frame(width: 24, height: 24)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isCustom ? Theme.text : Theme.strokeUp, lineWidth: isCustom ? 2 : 1)
                .padding(isCustom ? -2 : 0)
        )
    }

    private func setAccent(_ hex: String) {
        TaskAccentStore.shared.setAccentHex(hex, for: task.id)
        localAccentOverride = hex
    }

    private func kebabRow(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(title)
                Spacer()
            }
            .font(.system(size: 12.5))
            .foregroundStyle(role == .destructive ? Color(hex: 0xE07A7A) : Theme.textMid)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func startRename() {
        showKebabMenu = false
        draftTitle = task.title
        editError = nil
        collapsed = false
        editing = .rename
    }

    private func startScheduleEdit() {
        showKebabMenu = false
        draftTaskType = task.taskType
        draftSchedule = task.schedule ?? "every:1d"
        editError = nil
        collapsed = false
        editing = .schedule
    }

    // MARK: - Body

    @ViewBuilder
    private var body_: some View {
        switch editing {
        case .rename:
            renameEditor
        case .schedule:
            scheduleEditor
        case .none:
            normalBody
        }
    }

    private var normalBody: some View {
        VStack(alignment: .leading, spacing: 6) {
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

            if let exportStatusMessage, !exportStatusMessage.isEmpty {
                Text(exportStatusMessage)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .padding(14)
    }

    private var instructionPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let family = task.recipeFamilyLabel {
                metadataBadge(family, tint: .blue)
            }
            Text(task.instruction)
                .font(.caption)
                .foregroundStyle(Theme.textDim)
                .lineLimit(2)
        }
    }

    private func metadataBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Theme.mono(10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var approvalCallout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.approvalContextLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            if let tool = task.waitingApprovalTool, !tool.isEmpty {
                Text("Tool: \(tool)")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.textDim)
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

    /// Derived from data already on hand (error, empty-state sections,
    /// failed status) — no backend field for this exists, so this is a
    /// best-effort signal, not an authoritative health check.
    private var resultNeedsReview: Bool {
        task.status == "failed"
            || task.error != nil
            || (task.resultSections?.contains { $0.isEmptyState } ?? false)
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
                    HStack(spacing: 7) {
                        Text(")_")
                            .font(Theme.mono(11, weight: .semibold))
                            .foregroundStyle(Theme.textFaint)

                        Text("LAST RESULT")
                            .font(Theme.mono(10, weight: .semibold))
                            .kerning(0.6)
                            .foregroundStyle(Theme.textDim)

                        Text(resultNeedsReview ? "NEEDS REVIEW" : "OK")
                            .font(Theme.mono(9.5, weight: .semibold))
                            .foregroundStyle(resultNeedsReview ? Color(hex: 0xE2A94B) : Color(hex: 0x4FC98C))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (resultNeedsReview ? Color(hex: 0xE2A94B) : Color(hex: 0x4FC98C)).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 6)
                            )

                        Spacer()

                        Image(systemName: showResult ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(Theme.textFaint)
                    }
                }
                .buttonStyle(.borderless)

                if !showResult {
                    Text(collapsedPreview)
                        .font(.caption)
                        .foregroundStyle(Theme.textMid)
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
                                    .foregroundStyle(section.isEmptyState ? Theme.textFaint : Theme.text)
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
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
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
                    .foregroundStyle(Theme.textMid)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .tint(accent)
            }
        }
        .frame(maxHeight: 200)
        .padding(10)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
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
                        .foregroundStyle(isEmptyState ? Theme.textFaint : Theme.textMid)
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

    // MARK: - Inline editors

    private var editorFieldBackground: some View {
        RoundedRectangle(cornerRadius: 8).fill(Theme.bg)
    }

    private var renameEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TASK NAME")
                .font(Theme.mono(9.5, weight: .semibold))
                .kerning(1.0)
                .foregroundStyle(Theme.textFaint)

            TextField("Task name", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(editorFieldBackground)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.45), lineWidth: 1))

            if let editError {
                Text(editError).font(.caption).foregroundStyle(.red)
            }

            editorActions(
                saveLabel: "Save name",
                canSave: !draftTitle.trimmingCharacters(in: .whitespaces).isEmpty,
                onSave: { await saveRename() }
            )
        }
        .padding(14)
    }

    private var schedulePreviewLabel: String {
        taskCadenceOptions.first { $0.key == draftSchedule }?.label ?? draftSchedule
    }

    private var scheduleEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FREQUENCY")
                .font(Theme.mono(9.5, weight: .semibold))
                .kerning(1.0)
                .foregroundStyle(Theme.textFaint)

            FlowChips(items: taskCadenceOptions, selectedKey: draftSchedule, accent: accent) { key in
                draftSchedule = key
                draftTaskType = "recurring"
            }

            HStack(spacing: 6) {
                Text("PREVIEW").font(Theme.mono(9.5, weight: .semibold)).kerning(1.0).foregroundStyle(Theme.textFaint)
                Text(schedulePreviewLabel).font(Theme.mono(11)).foregroundStyle(accent)
            }

            if let editError {
                Text(editError).font(.caption).foregroundStyle(.red)
            }

            editorActions(
                saveLabel: "Save schedule",
                canSave: true,
                onSave: { await saveSchedule() }
            )
        }
        .padding(14)
    }

    private func editorActions(saveLabel: String, canSave: Bool, onSave: @escaping () async -> Void) -> some View {
        HStack(spacing: 9) {
            Spacer()
            Button("Cancel") {
                editing = .none
                editError = nil
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textMid)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.strokeUp, lineWidth: 1))
            .disabled(isSavingEdit)

            Button {
                Task { await onSave() }
            } label: {
                if isSavingEdit {
                    ProgressView().controlSize(.small).frame(width: 70)
                } else {
                    Text(saveLabel).padding(.horizontal, 14)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.bg)
            .padding(.vertical, 7)
            .background(accent, in: RoundedRectangle(cornerRadius: 8))
            .disabled(!canSave || isSavingEdit)
        }
    }

    private func updateRequest(title: String, taskType: String, schedule: String?) -> TaskUpdateRequest {
        TaskUpdateRequest(
            title: title,
            instruction: task.instruction,
            taskType: taskType,
            llmModelOverride: task.llmModelOverride,
            schedule: schedule,
            deliver: task.deliver,
            requiresApproval: task.requiresApproval,
            activeHoursStart: task.activeHoursStart,
            activeHoursEnd: task.activeHoursEnd,
            activeHoursTz: task.activeHoursTz,
            recipeFamily: task.taskRecipe?.family,
            recipeParams: task.taskRecipe?.params
        )
    }

    @MainActor
    private func saveRename() async {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSavingEdit = true
        editError = nil
        defer { isSavingEdit = false }
        do {
            let api = APIClient(authManager: authManager)
            _ = try await api.updateTask(task.id, updateRequest(title: trimmed, taskType: task.taskType, schedule: task.schedule))
            editing = .none
            onUpdated?()
        } catch {
            editError = "Could not save name."
        }
    }

    @MainActor
    private func saveSchedule() async {
        isSavingEdit = true
        editError = nil
        defer { isSavingEdit = false }
        do {
            let api = APIClient(authManager: authManager)
            _ = try await api.updateTask(task.id, updateRequest(title: task.title, taskType: draftTaskType, schedule: draftSchedule))
            editing = .none
            onUpdated?()
        } catch {
            editError = "Could not save schedule."
        }
    }

    // MARK: - Footer

    private var replyButton: some View {
        Button {
            onReplyInChat?()
        } label: {
            Label("Reply in Chat", systemImage: "bubble.left.and.text.bubble.right")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textMid)
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.strokeUp, lineWidth: 1))
    }

    @ViewBuilder
    private var footer: some View {
        if task.canRun || task.canReset || task.canStop || (task.isAgentTask && hasAnyResult) || task.result != nil {
            HStack(spacing: 9) {
                if task.canRun {
                    footerButton("Run", systemImage: "play.fill", filled: true) { onRun?() }
                }
                if task.canReset {
                    footerButton("Reset", systemImage: "arrow.counterclockwise") { onReset?() }
                }
                if task.canStop {
                    footerButton(task.isRunning ? "Stop Task" : "Stop", systemImage: "stop.fill") { onStop?() }
                }
                if task.isAgentTask && hasAnyResult {
                    footerButton(isExporting ? "Exporting…" : "Export", systemImage: "square.and.arrow.down") {
                        Task { await exportFindings() }
                    }
                    .disabled(isExporting)
                }

                Spacer(minLength: 8)

                if task.result != nil {
                    replyButton
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.012))
            .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .top)
        }
    }

    private func footerButton(_ title: String, systemImage: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(filled ? Theme.bg : Theme.textMid)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            if filled {
                RoundedRectangle(cornerRadius: 8).fill(accent)
                    .shadow(color: accent.opacity(0.45), radius: 6)
            } else {
                RoundedRectangle(cornerRadius: 8).stroke(Theme.strokeUp, lineWidth: 1)
            }
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
        .padding(.top, 4)
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

// MARK: - Cadence chip wrap

private struct FlowChips: View {
    let items: [(key: String, label: String)]
    let selectedKey: String
    let accent: Color
    let onSelect: (String) -> Void

    var body: some View {
        // Cadence options are few and short — a simple HStack wraps acceptably
        // at the card's fixed width without needing a custom flow layout.
        HStack(spacing: 6) {
            ForEach(items, id: \.key) { item in
                let isSelected = item.key == selectedKey
                Button {
                    onSelect(item.key)
                } label: {
                    Text(item.label)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(isSelected ? Theme.bg : Theme.textMid)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6).fill(accent)
                            } else {
                                RoundedRectangle(cornerRadius: 6).stroke(Theme.strokeUp, lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
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
            resolvedAgent: nil,
            lastRunAt: Date(),
            nextRunAt: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
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
                resolvedAgent: nil,
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
            resolvedAgent: nil,
            lastRunAt: Date(timeIntervalSinceNow: -3600),
            nextRunAt: Date(timeIntervalSinceNow: 1800),
            currentStepTitle: nil,
            waitingApprovalTool: nil
        ))
    }
}
