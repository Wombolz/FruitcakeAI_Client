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
    var projectId: Int?
    var isPinned: Bool?
    var lastActivity: Date
    var isLocal: Bool                  // true when created in on-device fallback mode

    @Relationship(deleteRule: .cascade)
    var messages: [CachedMessage]

    init(
        id: UUID = UUID(),
        serverSessionId: Int? = nil,
        title: String = "New conversation",
        persona: String = "family_assistant",
        projectId: Int? = nil,
        isPinned: Bool = false,
        lastActivity: Date = .now,
        isLocal: Bool = false
    ) {
        self.id = id
        self.serverSessionId = serverSessionId
        self.title = title
        self.persona = persona
        self.projectId = projectId
        self.isPinned = isPinned
        self.lastActivity = lastActivity
        self.isLocal = isLocal
        self.messages = []
    }

    var sortedMessages: [CachedMessage] {
        messages.sorted {
            if $0.timestamp != $1.timestamp {
                return $0.timestamp < $1.timestamp
            }
            if $0.serverMessageId != $1.serverMessageId {
                return ($0.serverMessageId ?? .max) < ($1.serverMessageId ?? .max)
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
