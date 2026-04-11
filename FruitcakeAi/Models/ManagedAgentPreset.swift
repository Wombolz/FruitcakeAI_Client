import Foundation

struct ManagedAgentPresetTaskSummary: Codable, Hashable {
    let id: Int
    let title: String
    let status: String
    let schedule: String?
    let lastRunAt: Date?
    let nextRunAt: Date?
}

struct ManagedAgentPresetLatestRunSummary: Codable, Hashable {
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

struct ManagedAgentPresetSummary: Codable, Identifiable, Hashable {
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
    let contextPaths: [String]
    let params: [String: JSONValue]
    let linkedTask: ManagedAgentPresetTaskSummary?
    let latestRun: ManagedAgentPresetLatestRunSummary?

    var id: String { presetId }

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

struct ManagedAgentPresetUpdateRequest: Encodable {
    let enabled: Bool?
    let autoMaintainTask: Bool?
    let schedule: String?
    let activeHoursStart: String?
    let activeHoursEnd: String?
    let activeHoursTz: String?
    let contextPaths: [String]?
    let params: [String: StringCodable]?

    private enum CodingKeys: String, CodingKey {
        case enabled, autoMaintainTask, schedule, activeHoursStart, activeHoursEnd, activeHoursTz, contextPaths, params
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let enabled { try container.encode(enabled, forKey: .enabled) }
        if let autoMaintainTask { try container.encode(autoMaintainTask, forKey: .autoMaintainTask) }
        if let schedule { try container.encode(schedule, forKey: .schedule) }
        if let activeHoursStart { try container.encode(activeHoursStart, forKey: .activeHoursStart) }
        if let activeHoursEnd { try container.encode(activeHoursEnd, forKey: .activeHoursEnd) }
        if let activeHoursTz { try container.encode(activeHoursTz, forKey: .activeHoursTz) }
        if let contextPaths { try container.encode(contextPaths, forKey: .contextPaths) }
        if let params { try container.encode(params, forKey: .params) }
    }
}

struct ManagedAgentPresetReconcileRequest: Encodable {
    let recreateMissing: Bool
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
        case .array(let values):
            return values.compactMap { $0.stringValue }
        case .string(let value):
            return [value]
        default:
            return []
        }
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
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
