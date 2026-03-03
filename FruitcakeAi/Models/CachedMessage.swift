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

    @Relationship(deleteRule: .nullify, inverse: \CachedConversation.messages)
    var conversation: CachedConversation?

    init(
        id: UUID = UUID(),
        serverMessageId: Int? = nil,
        role: String,
        content: String,
        timestamp: Date = .now,
        toolCalls: [String]? = nil,
        isLocal: Bool = false
    ) {
        self.id = id
        self.serverMessageId = serverMessageId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.isLocal = isLocal
    }

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
}
