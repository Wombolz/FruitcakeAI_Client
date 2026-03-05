//
//  Memory.swift
//  FruitcakeAi
//
//  Codable model for Phase 4 memory endpoints.
//  Decoded from GET /memories via APIClient (convertFromSnakeCase + ISO8601 dates).
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

    // MARK: - Computed

    var typeColor: Color {
        switch memoryType {
        case "procedural": return .purple
        case "semantic":   return .blue
        case "episodic":   return .teal
        default:           return .gray
        }
    }

    /// Five-dot importance indicator e.g. "●●●○○"
    var importanceDots: String {
        let filled = Int((importance * 5).rounded())
        return String(repeating: "●", count: filled) +
               String(repeating: "○", count: max(0, 5 - filled))
    }

    /// Three-letter type abbreviation for compact badges
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
