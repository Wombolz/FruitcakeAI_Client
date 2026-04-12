import Foundation

struct AgentInstanceTaskSummary: Codable, Hashable {
    let id: Int
    let title: String
    let status: String
    let schedule: String?
    let lastRunAt: Date?
    let nextRunAt: Date?
}

struct AgentInstanceLatestRunSummary: Codable, Hashable {
    let id: Int
    let status: String
    let runKind: String
    let startedAt: Date
    let finishedAt: Date?
    let summary: String?
    let error: String?

    var statusLabel: String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct AgentInstanceSummary: Codable, Identifiable, Hashable {
    let id: Int
    let presetId: String
    let displayName: String
    let category: String
    let categoryDisplayName: String
    let whenToUse: String
    let executionMode: String
    let background: Bool
    let enabled: Bool
    let autoMaintainTask: Bool
    let schedule: String?
    let activeHoursStart: String?
    let activeHoursEnd: String?
    let activeHoursTz: String?
    let llmModelOverride: String?
    let contextPaths: [String]
    let params: [String: JSONValue]
    let linkedTask: AgentInstanceTaskSummary?
    let latestRun: AgentInstanceLatestRunSummary?

    var categoryLabel: String {
        if !categoryDisplayName.isEmpty { return categoryDisplayName }
        return category.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var scheduleLabel: String {
        guard let schedule, !schedule.isEmpty else { return "Manual only" }
        switch schedule {
        case "every:6h": return "Every 6 hours"
        case "every:12h": return "Every 12 hours"
        case "every:1d": return "Daily"
        default: return schedule
        }
    }

    var backgroundLabel: String {
        background ? "Background-capable" : "Foreground"
    }
}

struct AgentInstanceUpdateRequest: Encodable {
    let displayName: String?
    let enabled: Bool?
    let autoMaintainTask: Bool?
    let schedule: String?
    let activeHoursStart: String?
    let activeHoursEnd: String?
    let activeHoursTz: String?
    let llmModelOverride: String?
    let contextPaths: [String]?
    let params: [String: StringCodable]?
}

struct AgentInstanceCreateRequest: Encodable {
    let presetId: String
    let displayName: String
    let enabled: Bool
    let autoMaintainTask: Bool
    let schedule: String?
    let activeHoursStart: String?
    let activeHoursEnd: String?
    let activeHoursTz: String?
    let llmModelOverride: String?
    let contextPaths: [String]?
    let params: [String: StringCodable]?
}

struct AgentInstanceReconcileRequest: Encodable {
    let recreateMissing: Bool
}

struct AgentPresetCategoryResponse: Codable {
    let categories: [AgentPresetCategoryGroup]
}

struct AgentPresetCategoryGroup: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let whenToUse: String
    let presets: [AgentPresetOption]
}

struct AgentPresetOption: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let category: String
    let categoryDisplayName: String
    let whenToUse: String
    let executionMode: String
    let background: Bool
    let memoryScope: String
    let personaCompatibility: String
    let requiredContextSources: [String]
    let outputContract: [String]

    var backgroundLabel: String {
        background ? "Background-capable" : executionMode.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

extension JSONValue {
    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .string(let value): return Bool(value)
        default: return nil
        }
    }

    var stringArrayValue: [String] {
        switch self {
        case .array(let values): return values.compactMap { $0.stringValue }
        case .string(let value): return [value]
        default: return []
        }
    }

    var stringCodableValue: StringCodable {
        switch self {
        case .string(let value): return .string(value)
        case .int(let value): return .int(value)
        case .double(let value): return .double(value)
        case .bool(let value): return .bool(value)
        case .array(let value): return .array(value.map { $0.stringCodableValue })
        case .object(let value): return .object(value.mapValues { $0.stringCodableValue })
        case .null: return .null
        }
    }
}
