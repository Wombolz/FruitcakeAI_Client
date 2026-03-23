//
//  GraphMemory.swift
//  FruitcakeAi
//
//  Codable models for graph-memory endpoints.
//

import Foundation

struct GraphMemoryEntitySummary: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let entityType: String
}

struct GraphMemoryEntityDetail: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let entityType: String
    let aliases: [String]
    let confidence: Double
    let isActive: Bool

    var displayType: String {
        entityType.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct GraphMemoryEntity: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let entityType: String
    let aliases: [String]
    let confidence: Double
    let isActive: Bool
    let relationCount: Int
    let observationCount: Int

    var displayType: String {
        entityType.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct GraphMemoryRelation: Identifiable, Codable, Hashable {
    let id: Int
    let fromEntity: GraphMemoryEntitySummary
    let toEntity: GraphMemoryEntitySummary
    let relationType: String
    let confidence: Double
    let sourceMemoryId: Int?
    let sourceSessionId: Int?
    let sourceTaskId: Int?

    var displayRelationType: String {
        relationType.replacingOccurrences(of: "_", with: " ")
    }
}

struct GraphMemoryObservation: Identifiable, Codable, Hashable {
    let id: Int
    let entityId: Int
    let content: String?
    let observedAt: Date?
    let confidence: Double
    let isActive: Bool
    let sourceMemoryId: Int?
    let sourceSessionId: Int?
    let sourceTaskId: Int?

    var provenanceLabel: String {
        if let sourceMemoryId {
            return "Derived from memory #\(sourceMemoryId)"
        }
        if let sourceSessionId {
            return "Observed in chat session #\(sourceSessionId)"
        }
        if let sourceTaskId {
            return "Observed in task #\(sourceTaskId)"
        }
        return "Graph observation"
    }
}

struct GraphMemoryNode: Codable, Hashable {
    let entity: GraphMemoryEntityDetail
    let relationCount: Int
    let observationCount: Int
    let relations: [GraphMemoryRelation]
    let observations: [GraphMemoryObservation]
}

struct GraphMemoryEntityPatch: Encodable {
    var name: String
    var entityType: String
    var aliases: [String]
    var confidence: Double
}

struct GraphMemoryObservationPatch: Encodable {
    var content: String?
    var observedAt: Date?
    var confidence: Double
}
