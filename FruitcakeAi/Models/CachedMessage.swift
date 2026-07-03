//
//  CachedMessage.swift
//  FruitcakeAi
//
//  SwiftData model for a single chat message.
//  Persisted locally so conversations survive between launches.
//

import Foundation
import SwiftData

@Model
final class CachedMessage {

    var id: UUID
    var serverMessageId: Int?          // backend message ID (nil for optimistic/local)
    var role: String                   // "user" or "assistant"
    var content: String
    var timestamp: Date
    var toolCalls: [String]?           // tool names invoked during this response
    var isLocal: Bool                  // true when created in on-device fallback mode
    var recalledMemoryIds: [Int]?      // memories injected into this turn's context

    // Inline task-draft card state — persisted so the card survives session
    // switch, history reload, and relaunch instead of only existing for the
    // lifetime of the live response that proposed it.
    //
    // Stored as raw JSON bytes rather than as TaskDraft directly: SwiftData's
    // own persisted-property storage calls TaskDraft's hand-rolled
    // init(from:) with its own internal decoder, which traps (not a
    // catchable Swift error — `try?` inside that initializer can't save it)
    // because that decoder isn't what TaskDraft's custom decoding expects.
    // Encoding/decoding it ourselves with a plain JSONEncoder/JSONDecoder
    // sidesteps SwiftData's native Codable-attribute path entirely.
    private var taskDraftData: Data?
    var taskDraftStatus: String?       // "draft" | "accepted" | "denied"
    var createdTaskId: Int?
    private var evidenceData: Data?

    var taskDraft: TaskDraft? {
        get {
            guard let taskDraftData else { return nil }
            return try? Self.decoder.decode(TaskDraft.self, from: taskDraftData)
        }
        set {
            taskDraftData = newValue.flatMap { try? Self.encoder.encode($0) }
        }
    }

    var evidence: ChatEvidenceMetadata? {
        get {
            guard let evidenceData else { return nil }
            return try? Self.decoder.decode(ChatEvidenceMetadata.self, from: evidenceData)
        }
        set {
            evidenceData = newValue.flatMap { try? Self.encoder.encode($0) }
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @Relationship(deleteRule: .nullify, inverse: \CachedConversation.messages)
    var conversation: CachedConversation?

    init(
        id: UUID = UUID(),
        serverMessageId: Int? = nil,
        role: String,
        content: String,
        timestamp: Date = .now,
        toolCalls: [String]? = nil,
        isLocal: Bool = false,
        taskDraft: TaskDraft? = nil,
        taskDraftStatus: String? = nil,
        createdTaskId: Int? = nil,
        evidence: ChatEvidenceMetadata? = nil,
        recalledMemoryIds: [Int]? = nil
    ) {
        self.id = id
        self.serverMessageId = serverMessageId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.isLocal = isLocal
        self.taskDraftStatus = taskDraftStatus
        self.createdTaskId = createdTaskId
        self.taskDraft = taskDraft
        self.evidence = evidence
        self.recalledMemoryIds = recalledMemoryIds
    }

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
}
