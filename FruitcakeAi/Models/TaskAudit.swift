//
//  TaskAudit.swift
//  FruitcakeAi
//
//  Models for GET /tasks/{id}/audit response.
//

import Foundation

struct TaskAuditEntry: Codable {
    let tool: String
    let arguments: [String: String]
    let resultSummary: String
    let createdAt: Date

    var id: String { "\(tool)-\(createdAt.timeIntervalSince1970)" }

    enum CodingKeys: String, CodingKey {
        case tool, arguments, resultSummary, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tool = try c.decode(String.self, forKey: .tool)
        resultSummary = try c.decode(String.self, forKey: .resultSummary)
        createdAt = try c.decode(Date.self, forKey: .createdAt)

        let raw = (try? c.decode([String: JSONValue].self, forKey: .arguments)) ?? [:]
        arguments = raw.mapValues { $0.stringValue }
    }
}

struct TaskAuditOut: Codable {
    let taskId: Int
    let title: String
    let result: String?
    let resolvedAgent: ResolvedAgentSummary?
    let toolCalls: [TaskAuditEntry]
}

private enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let value = try? c.decode(String.self) {
            self = .string(value)
        } else if let value = try? c.decode(Int.self) {
            self = .int(value)
        } else if let value = try? c.decode(Double.self) {
            self = .double(value)
        } else if let value = try? c.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? c.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? c.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let value): try c.encode(value)
        case .int(let value): try c.encode(value)
        case .double(let value): try c.encode(value)
        case .bool(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .null: try c.encodeNil()
        }
    }

    var stringValue: String {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        case .null:
            return "null"
        case .object(let value):
            if let data = try? JSONEncoder().encode(value),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            return "{...}"
        case .array(let value):
            if let data = try? JSONEncoder().encode(value),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            return "[...]"
        }
    }
}
