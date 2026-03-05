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
}

struct TaskAuditOut: Codable {
    let taskId: Int
    let title: String
    let result: String?
    let toolCalls: [TaskAuditEntry]
}
