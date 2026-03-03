//
//  CachedConversation.swift
//  FruitcakeAi
//
//  SwiftData model for a chat conversation (session).
//  Mirrors the backend ChatSession; messages cached locally for offline access.
//

import Foundation
import SwiftData

@Model
final class CachedConversation {

    var id: UUID
    var serverSessionId: Int?          // backend session ID (nil if local-only)
    var title: String
    var persona: String
    var lastActivity: Date
    var isLocal: Bool                  // true when created in on-device fallback mode

    @Relationship(deleteRule: .cascade)
    var messages: [CachedMessage]

    init(
        id: UUID = UUID(),
        serverSessionId: Int? = nil,
        title: String = "New conversation",
        persona: String = "family_assistant",
        lastActivity: Date = .now,
        isLocal: Bool = false
    ) {
        self.id = id
        self.serverSessionId = serverSessionId
        self.title = title
        self.persona = persona
        self.lastActivity = lastActivity
        self.isLocal = isLocal
        self.messages = []
    }

    var sortedMessages: [CachedMessage] {
        messages.sorted { $0.timestamp < $1.timestamp }
    }
}
