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
    let status: String
    let taskType: String            // "one_shot" | "recurring"
    let schedule: String?
    let deliver: Bool
    let requiresApproval: Bool
    let result: String?
    let error: String?
    let lastRunAt: Date?
    let nextRunAt: Date?
    let currentStepTitle: String?
    let waitingApprovalTool: String?

    // MARK: - Computed

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

    var approvalContextLabel: String {
        if let step = currentStepTitle, !step.isEmpty {
            return "Waiting on step: \(step)"
        }
        if let tool = waitingApprovalTool, !tool.isEmpty {
            return "Approval needed for tool: \(tool)"
        }
        return "Approval required"
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

// MARK: - CreateTaskRequest

struct CreateTaskRequest: Encodable {
    let title: String
    let instruction: String
    let taskType: String            // "one_shot" | "recurring"
    let schedule: String?           // nil for one_shot; "every:1h" etc. for recurring
    let deliver: Bool
    let requiresApproval: Bool
    let activeHoursStart: String?   // "HH:mm" or nil
    let activeHoursEnd: String?     // "HH:mm" or nil
    let activeHoursTz: String?      // e.g. "America/Chicago" or nil
}
