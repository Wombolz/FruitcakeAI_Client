//
//  Task.swift
//  FruitcakeAi
//
//  Codable models for Phase 4 task endpoints.
//  Decoded from GET/POST /tasks via APIClient (convertFromSnakeCase + ISO8601 dates).
//

import SwiftUI

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
    let error: String?
    let activeHoursStart: String?
    let activeHoursEnd: String?
    let activeHoursTz: String?
    let effectiveTimezone: String?
    let taskRecipe: TaskRecipeMetadata?
    let lastRunAt: Date?
    let nextRunAt: Date?
    let currentStepTitle: String?
    let waitingApprovalTool: String?

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
