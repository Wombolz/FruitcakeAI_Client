//
//  Memory.swift
//  FruitcakeAi
//
//  Codable models for flat memory and memory review endpoints.
//

import SwiftUI

struct MemorySummary: Identifiable, Codable {
    let id: Int
    let content: String
    let memoryType: String          // "episodic" | "semantic" | "procedural"
    let importance: Double          // 0.0–1.0
    let accessCount: Int
    let tags: [String]
    let createdAt: Date
    let expiresAt: Date?

    var typeColor: Color {
        switch memoryType {
        case "procedural": return .purple
        case "semantic":   return .blue
        case "episodic":   return .teal
        default:           return .gray
        }
    }

    var importanceDots: String {
        let filled = Int((importance * 5).rounded())
        return String(repeating: "●", count: filled) +
               String(repeating: "○", count: max(0, 5 - filled))
    }

    var typeAbbreviation: String {
        switch memoryType {
        case "procedural": return "PRO"
        case "semantic":   return "SEM"
        case "episodic":   return "EPI"
        default:           return "???"
        }
    }

    var typeDisplayName: String {
        memoryType.capitalized
    }
}

struct MemoryBulkDeleteResponse: Codable {
    let deactivatedCount: Int
    let deletedAt: Date
}

struct MemoryReviewProposalPayload: Codable, Hashable {
    let proposalKey: String?
    let memoryType: String
    let content: String
    let topic: String?
    let supportingUrls: [String]
    let sourceNames: [String]
    let reason: String?
    let confidence: Double?
}

struct MemoryReviewProposal: Identifiable, Codable, Hashable {
    let id: Int
    let proposalType: String
    let sourceType: String
    let status: String
    let taskId: Int?
    let taskRunId: Int?
    let content: String
    let confidence: Double
    let reason: String?
    let createdAt: Date?
    let resolvedAt: Date?
    let resolvedByUserId: Int?
    let approvedMemoryId: Int?
    let proposal: MemoryReviewProposalPayload

    var isPending: Bool { status == "pending" }

    var statusDisplayName: String {
        switch status {
        case "pending": return "Pending"
        case "approved": return "Approved"
        case "rejected": return "Rejected"
        default: return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var statusColor: Color {
        switch status {
        case "pending": return .orange
        case "approved": return .green
        case "rejected": return .secondary
        default: return .gray
        }
    }

    var sourceDisplayName: String {
        sourceType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var memoryTypeDisplayName: String {
        proposal.memoryType.capitalized
    }

    var confidencePercent: Int {
        Int((confidence * 100).rounded())
    }

    var summaryReason: String? {
        let candidate = (reason ?? proposal.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? nil : candidate
    }

    var topicDisplay: String? {
        let candidate = (proposal.topic ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? nil : candidate
    }

    var supportingURLValues: [URL] {
        proposal.supportingUrls.compactMap(URL.init(string:))
    }
}

struct MemoryReviewApprovalResponse: Codable {
    let proposal: MemoryReviewProposal
    let memory: MemorySummary
}

struct LLMUsageEventSummary: Identifiable, Codable, Hashable {
    let scopeLabel: String
    let taskId: Int?
    let sessionId: Int?
    let taskRunId: Int?
    let source: String
    let stage: String?
    let model: String
    let totalTokens: Int
    let estimatedCostUsd: Double?
    let createdAt: Date?

    var id: String {
        "\(scopeLabel)-\(createdAt?.timeIntervalSince1970 ?? 0)-\(model)"
    }

    var stageDisplay: String {
        let candidate = (stage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? source.replacingOccurrences(of: "_", with: " ").capitalized : candidate.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var costDisplay: String {
        guard let estimatedCostUsd else { return "n/a" }
        return String(format: "$%.4f", estimatedCostUsd)
    }
}
