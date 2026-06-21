//
//  Task.swift
//  FruitcakeAi
//
//  Codable models for Phase 4 task endpoints.
//  Decoded from GET/POST /tasks via APIClient (convertFromSnakeCase + ISO8601 dates).
//

import SwiftUI

// MARK: - TaskResultSection

struct TaskResultSection: Codable {
    let heading: String
    let body: String
    let isEmptyState: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        heading = try container.decodeIfPresent(String.self, forKey: .heading) ?? ""
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        isEmptyState = try container.decodeIfPresent(Bool.self, forKey: .isEmptyState) ?? false
    }
}

struct ResolvedAgentSummary: Codable, Hashable {
    let id: String
    let displayName: String
    let category: String
    let categoryDisplayName: String
    let executionMode: String
    let background: Bool
    let memoryScope: String
    let personaCompatibility: String?
    let whenToUse: String

    var categoryLabel: String {
        if !categoryDisplayName.isEmpty {
            return categoryDisplayName
        }
        return category.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var executionModeLabel: String {
        executionMode.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var memoryScopeLabel: String {
        memoryScope.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - TaskSummary

struct TaskSummary: Identifiable, Codable {
    let id: Int
    let title: String
    let instruction: String
    let persona: String?
    let profile: String?
    let llmModelOverride: String?
    let status: String
    let taskType: String            // "one_shot" | "recurring"
    let schedule: String?
    let deliver: Bool
    let requiresApproval: Bool
    let result: String?
    var resultMarkdown: String? = nil
    var resultFormat: String? = nil
    var resultSections: [TaskResultSection]? = nil
    let error: String?
    let activeHoursStart: String?
    let activeHoursEnd: String?
    let activeHoursTz: String?
    let effectiveTimezone: String?
    let taskRecipe: TaskRecipeMetadata?
    let resolvedAgent: ResolvedAgentSummary?
    let lastRunAt: Date?
    let nextRunAt: Date?
    let currentStepTitle: String?
    let waitingApprovalTool: String?
    var presentation: TaskPresentationMetadata? = nil

    var hasRichResult: Bool {
        !(resultSections?.isEmpty ?? true) || resultMarkdown != nil
    }

    /// Per-task accent driving the card's left rail, Run button, agent label,
    /// and result prompt. Backend-persisted (`presentation.accentHex`) takes
    /// priority once set; falls back to a local-only override (see
    /// TaskAccentStore) and finally to the same deterministic hash used for
    /// chat persona accents — one color system, not a second one.
    var accent: Color {
        if let hex = presentation?.accentHex, let color = Color(taskAccentHex: hex) {
            return color
        }
        if let overrideHex = TaskAccentStore.shared.accentHex(for: id), let color = Color(taskAccentHex: overrideHex) {
            return color
        }
        return PersonaAccent.color(for: persona ?? agentRoleLabel ?? title)
    }

    var statusColor: Color {
        switch status {
        case "completed":        return .green
        case "running":          return .blue
        case "failed":           return .red
        case "waiting_approval": return .orange
        case "cancelled":        return .gray
        default:                 return .gray
        }
    }

    var statusLabel: String {
        switch status {
        case "completed":        return "Completed"
        case "running":          return "Running"
        case "failed":           return "Failed"
        case "waiting_approval": return "Needs Approval"
        case "pending":          return "Pending"
        case "cancelled":        return "Cancelled"
        default:                 return status.capitalized
        }
    }

    var isPendingApproval: Bool { status == "waiting_approval" }
    var isRunning: Bool { status == "running" }
    var canStop: Bool { status == "running" || status == "pending" }
    var canRun: Bool { status != "running" && status != "waiting_approval" }
    var canReset: Bool { status == "completed" || status == "failed" || status == "cancelled" }

    var approvalContextLabel: String {
        if let step = currentStepTitle, !step.isEmpty {
            return "Waiting on step: \(step)"
        }
        if let tool = waitingApprovalTool, !tool.isEmpty {
            return "Approval needed for tool: \(tool)"
        }
        return "Approval required"
    }

    var recipeFamilyLabel: String? {
        guard let family = taskRecipe?.family, !family.isEmpty else { return nil }
        return family.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var isAgentTask: Bool {
        taskRecipe?.family == "agent"
    }

    var agentRoleLabel: String? {
        if let displayName = resolvedAgent?.displayName, !displayName.isEmpty {
            return displayName
        }
        guard let role = taskRecipe?.paramString("agent_role"), !role.isEmpty else { return nil }
        return role
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    var contextPaths: [String] {
        taskRecipe?.paramStringArray("context_paths") ?? []
    }

    var scheduleLabel: String? {
        guard let schedule, !schedule.isEmpty else {
            return taskType == "one_shot" ? "One time" : nil
        }
        switch schedule {
        case "every:30m": return "Every 30 min"
        case "every:1h": return "Every hour"
        case "every:6h": return "Every 6 hours"
        case "every:12h": return "Every 12 hours"
        case "every:1d": return "Daily"
        default: return schedule
        }
    }
}

struct TaskStepSummary: Identifiable, Codable {
    let id: Int
    let stepIndex: Int
    let title: String
    let instruction: String
    let status: String
    let requiresApproval: Bool
    let outputSummary: String?
    let error: String?
    let waitingApprovalTool: String?
}

struct TaskResultExportResponse: Codable {
    let exported: Bool
    let taskId: Int
    let runId: Int
    let path: String
    let sourceArtifactType: String
}

struct TaskRecipeMetadata: Codable, Hashable {
    let family: String?
    let confidence: String?
    let params: [String: StringCodable]?
    let assumptions: [String]?
    let selectedProfile: String?
    let selectedExecutorKind: String?
    let instructionStyle: String?

    func paramString(_ key: String) -> String? {
        params?[key]?.stringValue
    }

    func paramInt(_ key: String) -> Int? {
        params?[key]?.intValue
    }

    func paramStringArray(_ key: String) -> [String] {
        params?[key]?.stringArrayValue ?? []
    }
}

struct TaskDraft: Identifiable, Codable, Hashable {
    var id: String {
        [title, taskRecipe?.family ?? "", schedule ?? "", nextRunAt?.ISO8601Format() ?? ""]
            .joined(separator: "|")
    }

    let proposed: Bool
    let title: String
    let instruction: String
    let persona: String?
    let profile: String?
    let taskRecipe: TaskRecipeMetadata?
    let taskSummary: String?
    let taskConfirmation: String?
    let executorKind: String?
    let llmModelOverride: String?
    let taskType: String
    let schedule: String?
    let deliver: Bool
    let requiresApproval: Bool
    let activeHoursStart: String?
    let activeHoursEnd: String?
    let activeHoursTz: String?
    let effectiveTimezone: String?
    let nextRunAt: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        proposed = (try? container.decode(Bool.self, forKey: .proposed)) ?? true
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        instruction = (try? container.decode(String.self, forKey: .instruction)) ?? ""
        persona = try? container.decode(String.self, forKey: .persona)
        profile = try? container.decode(String.self, forKey: .profile)
        taskRecipe = try? container.decode(TaskRecipeMetadata.self, forKey: .taskRecipe)
        taskSummary = try? container.decode(String.self, forKey: .taskSummary)
        taskConfirmation = try? container.decode(String.self, forKey: .taskConfirmation)
        executorKind = try? container.decode(String.self, forKey: .executorKind)
        llmModelOverride = try? container.decode(String.self, forKey: .llmModelOverride)
        taskType = (try? container.decode(String.self, forKey: .taskType)) ?? "one_shot"
        schedule = try? container.decode(String.self, forKey: .schedule)
        deliver = (try? container.decode(Bool.self, forKey: .deliver)) ?? true
        requiresApproval = (try? container.decode(Bool.self, forKey: .requiresApproval)) ?? true
        activeHoursStart = try? container.decode(String.self, forKey: .activeHoursStart)
        activeHoursEnd = try? container.decode(String.self, forKey: .activeHoursEnd)
        activeHoursTz = try? container.decode(String.self, forKey: .activeHoursTz)
        effectiveTimezone = try? container.decode(String.self, forKey: .effectiveTimezone)
        nextRunAt = try? container.decode(Date.self, forKey: .nextRunAt)
    }

    private enum CodingKeys: String, CodingKey {
        case proposed, title, instruction, persona, profile, taskRecipe
        case taskSummary, taskConfirmation, executorKind, llmModelOverride
        case taskType, schedule, deliver, requiresApproval
        case activeHoursStart, activeHoursEnd, activeHoursTz, effectiveTimezone, nextRunAt
    }

    var detailSummary: String {
        let summary = taskSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return summary.isEmpty ? instruction : summary
    }

    var scheduleLabel: String? {
        guard let schedule, !schedule.isEmpty else {
            return taskType == "one_shot" ? "One time" : nil
        }
        switch schedule {
        case "every:30m": return "Every 30 min"
        case "every:1h": return "Every hour"
        case "every:6h": return "Every 6 hours"
        case "every:12h": return "Every 12 hours"
        case "every:1d": return "Daily"
        default: return schedule
        }
    }

    var dueSummary: String? {
        if let nextRunAt {
            return nextRunAt.formatted(date: .abbreviated, time: .shortened)
        }
        return scheduleLabel
    }
}

/// Shared shape for the `metadata` object attached to assistant chat messages —
/// decoded identically from chat history, the REST send response, and the
/// WebSocket `done` event so an inline task-draft card behaves the same
/// regardless of which path produced the message.
///
/// `taskDraft` decodes defensively: the WebSocket path silently drops the
/// entire incoming frame (losing the whole response) if WSPayload decoding
/// throws anywhere, so a malformed/evolving draft shape must not take the
/// rest of the metadata down with it.
struct ChatMessageMetadata: Decodable {
    let taskDraft: TaskDraft?
    let taskDraftStatus: String?
    let createdTaskId: Int?
    let toolCalls: [String]?

    private enum CodingKeys: String, CodingKey {
        case taskDraft, taskDraftStatus, createdTaskId, toolCalls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            taskDraft = try container.decodeIfPresent(TaskDraft.self, forKey: .taskDraft)
        } catch {
            print("[ChatTrace] task_draft_decode_error: \(error)")
            taskDraft = nil
        }
        taskDraftStatus = try container.decodeIfPresent(String.self, forKey: .taskDraftStatus)
        createdTaskId = try container.decodeIfPresent(Int.self, forKey: .createdTaskId)
        toolCalls = try container.decodeIfPresent([String].self, forKey: .toolCalls)
    }
}

struct AcceptTaskDraftResponse: Decodable {
    let created: Bool
    let reusedExisting: Bool
    let taskId: Int
    let title: String
    let metadata: ChatMessageMetadata
}

struct DenyTaskDraftResponse: Decodable {
    let denied: Bool
    let metadata: ChatMessageMetadata
}

/// Additive task presentation metadata. Absent entirely on tasks created
/// before the backend supported it — always optional, never assumed present.
struct TaskPresentationMetadata: Codable, Hashable {
    let accentHex: String?
}

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    /// Parses a "#RRGGBB" or "RRGGBB" task accent hex string. Returns nil for
    /// anything malformed rather than guessing — callers fall through to the
    /// next accent source.
    init?(taskAccentHex hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6, let value = UInt(trimmed, radix: 16) else { return nil }
        self = Color(hex: value)
    }

    /// Exports as "#RRGGBB" — used to persist a custom color picked via the
    /// task accent hue-wheel swatch.
    func taskAccentHexString() -> String {
        #if os(macOS)
        let resolved = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let r = Int((resolved.redComponent * 255).rounded())
        let g = Int((resolved.greenComponent * 255).rounded())
        let b = Int((resolved.blueComponent * 255).rounded())
        #else
        let resolved = UIColor(self)
        var rf: CGFloat = 0, gf: CGFloat = 0, bf: CGFloat = 0, af: CGFloat = 0
        resolved.getRed(&rf, green: &gf, blue: &bf, alpha: &af)
        let r = Int((rf * 255).rounded())
        let g = Int((gf * 255).rounded())
        let b = Int((bf * 255).rounded())
        #endif
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

struct CreateTaskRequest: Encodable {
    let title: String
    let instruction: String
    let llmModelOverride: String?
    let taskType: String
    let schedule: String?
    let deliver: Bool
    let requiresApproval: Bool
    let activeHoursStart: String?
    let activeHoursEnd: String?
    let activeHoursTz: String?
    let recipeFamily: String?
    let recipeParams: [String: StringCodable]?
}

struct TaskUpdateRequest: Encodable {
    private enum CodingKeys: String, CodingKey {
        case title, instruction, taskType, llmModelOverride, schedule, deliver, requiresApproval, activeHoursStart, activeHoursEnd, activeHoursTz, recipeFamily, recipeParams
    }

    let title: String
    let instruction: String
    let taskType: String
    let llmModelOverride: String?
    let schedule: String?
    let deliver: Bool
    let requiresApproval: Bool
    let activeHoursStart: String?
    let activeHoursEnd: String?
    let activeHoursTz: String?
    let recipeFamily: String?
    let recipeParams: [String: StringCodable]?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(instruction, forKey: .instruction)
        try container.encode(taskType, forKey: .taskType)
        if let llmModelOverride {
            try container.encode(llmModelOverride, forKey: .llmModelOverride)
        } else {
            try container.encodeNil(forKey: .llmModelOverride)
        }
        if let schedule {
            try container.encode(schedule, forKey: .schedule)
        } else {
            try container.encodeNil(forKey: .schedule)
        }
        try container.encode(deliver, forKey: .deliver)
        try container.encode(requiresApproval, forKey: .requiresApproval)
        if let activeHoursStart {
            try container.encode(activeHoursStart, forKey: .activeHoursStart)
        } else {
            try container.encodeNil(forKey: .activeHoursStart)
        }
        if let activeHoursEnd {
            try container.encode(activeHoursEnd, forKey: .activeHoursEnd)
        } else {
            try container.encodeNil(forKey: .activeHoursEnd)
        }
        if let activeHoursTz {
            try container.encode(activeHoursTz, forKey: .activeHoursTz)
        } else {
            try container.encodeNil(forKey: .activeHoursTz)
        }
        if let recipeFamily {
            try container.encode(recipeFamily, forKey: .recipeFamily)
        } else {
            try container.encodeNil(forKey: .recipeFamily)
        }
        if let recipeParams {
            try container.encode(recipeParams, forKey: .recipeParams)
        } else {
            try container.encodeNil(forKey: .recipeParams)
        }
    }
}

enum StringCodable: Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([StringCodable])
    case object([String: StringCodable])
    case null

    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        default:
            return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .string(let value):
            return Int(value)
        default:
            return nil
        }
    }

    var stringArrayValue: [String] {
        switch self {
        case .array(let values):
            return values.compactMap { $0.stringValue }
        case .string(let value):
            return [value]
        default:
            return []
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([StringCodable].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: StringCodable].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
